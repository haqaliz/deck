use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::time::Instant;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct NetCounters {
    pub rx_bytes: u64,
    pub rx_packets: u64,
    pub rx_errors: u64,
    pub tx_bytes: u64,
    pub tx_packets: u64,
    pub tx_errors: u64,
}

/// Parse `/proc/net/dev`. The two header lines are skipped; the rest are
/// `iface: rx_bytes rx_packets rx_errs ... tx_bytes tx_packets tx_errs ...`.
pub fn parse_net_dev(text: &str) -> BTreeMap<String, NetCounters> {
    let mut interfaces = BTreeMap::new();
    for line in text.lines().skip(2) {
        let Some((name, rest)) = line.split_once(':') else {
            continue;
        };
        let name = name.trim();
        let fields: Vec<&str> = rest.split_whitespace().collect();
        if fields.len() < 11 {
            continue;
        }
        let parse = |index: usize| {
            fields
                .get(index)
                .and_then(|value| value.parse::<u64>().ok())
        };
        interfaces.insert(
            name.to_string(),
            NetCounters {
                rx_bytes: parse(0).unwrap_or(0),
                rx_packets: parse(1).unwrap_or(0),
                rx_errors: parse(2).unwrap_or(0),
                tx_bytes: parse(8).unwrap_or(0),
                tx_packets: parse(9).unwrap_or(0),
                tx_errors: parse(10).unwrap_or(0),
            },
        );
    }
    interfaces
}

#[derive(Debug, Clone, PartialEq)]
pub struct InterfaceRate {
    pub name: String,
    pub rx_bytes_per_second: f64,
    pub tx_bytes_per_second: f64,
    pub rx_packets_per_second: f64,
    pub tx_packets_per_second: f64,
    pub rx_errors: u64,
    pub tx_errors: u64,
}

pub fn rates(
    previous: &BTreeMap<String, NetCounters>,
    current: &BTreeMap<String, NetCounters>,
    seconds: f64,
) -> Vec<InterfaceRate> {
    if seconds <= 0.0 {
        return Vec::new();
    }
    current
        .iter()
        .filter_map(|(name, now)| {
            let before = previous.get(name)?;
            Some(InterfaceRate {
                name: name.clone(),
                rx_bytes_per_second: now.rx_bytes.saturating_sub(before.rx_bytes) as f64 / seconds,
                tx_bytes_per_second: now.tx_bytes.saturating_sub(before.tx_bytes) as f64 / seconds,
                rx_packets_per_second: now.rx_packets.saturating_sub(before.rx_packets) as f64
                    / seconds,
                tx_packets_per_second: now.tx_packets.saturating_sub(before.tx_packets) as f64
                    / seconds,
                rx_errors: now.rx_errors,
                tx_errors: now.tx_errors,
            })
        })
        .collect()
}

#[derive(Debug, Default)]
pub struct NetSampler {
    previous: Option<(Instant, BTreeMap<String, NetCounters>)>,
}

impl NetSampler {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn sample(&mut self) -> io::Result<Vec<InterfaceRate>> {
        let text = fs::read_to_string("/proc/net/dev")?;
        let current = parse_net_dev(&text);
        let now = Instant::now();
        let rates = self
            .previous
            .as_ref()
            .map(|(at, previous)| rates(previous, &current, now.duration_since(*at).as_secs_f64()))
            .unwrap_or_default();
        self.previous = Some((now, current));
        let mut rates = rates;
        rates.sort_by(|left, right| {
            (right.rx_bytes_per_second + right.tx_bytes_per_second)
                .partial_cmp(&(left.rx_bytes_per_second + left.tx_bytes_per_second))
                .unwrap_or(std::cmp::Ordering::Equal)
        });
        Ok(rates)
    }
}

/// Total down/up across real interfaces; loopback is excluded so browsing
/// localhost does not look like internet traffic.
pub fn totals(rates: &[InterfaceRate]) -> (f64, f64) {
    rates
        .iter()
        .filter(|rate| rate.name != "lo")
        .fold((0.0, 0.0), |(down, up), rate| {
            (
                down + rate.rx_bytes_per_second,
                up + rate.tx_bytes_per_second,
            )
        })
}

/// Interface names from `/proc/net/dev`; used by search, which needs names
/// rather than rates.
pub fn interface_names() -> Vec<String> {
    fs::read_to_string("/proc/net/dev")
        .map(|text| parse_net_dev(&text).into_keys().collect())
        .unwrap_or_default()
}

pub fn format_rate(bytes_per_second: f64) -> String {
    if bytes_per_second >= 1_000_000.0 {
        format!("{:.1} MB/s", bytes_per_second / 1_000_000.0)
    } else if bytes_per_second >= 1_000.0 {
        format!("{:.1} KB/s", bytes_per_second / 1_000.0)
    } else {
        format!("{:.0} B/s", bytes_per_second)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURE: &str = "Inter-|   Receive                                                |  Transmit\n face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n    lo: 1000 10 0 0 0 0 0 0 2000 20 0 0 0 0 0 0\n  eth0: 5000 50 1 0 0 0 0 0 7000 70 2 0 0 0 0 0\n";

    #[test]
    fn parses_interfaces_and_errors() {
        let interfaces = parse_net_dev(FIXTURE);
        let eth0 = interfaces.get("eth0").expect("eth0");
        assert_eq!(eth0.rx_bytes, 5000);
        assert_eq!(eth0.tx_packets, 70);
        assert_eq!(eth0.rx_errors, 1);
        assert_eq!(eth0.tx_errors, 2);
    }

    #[test]
    fn computes_rates_from_two_samples() {
        let previous = parse_net_dev(FIXTURE);
        let mut current = previous.clone();
        current.get_mut("eth0").expect("eth0").rx_bytes += 1000;
        current.get_mut("eth0").expect("eth0").tx_bytes += 2000;
        let rates = rates(&previous, &current, 2.0);
        let eth0 = rates
            .iter()
            .find(|rate| rate.name == "eth0")
            .expect("eth0 rate");
        assert_eq!(eth0.rx_bytes_per_second, 500.0);
        assert_eq!(eth0.tx_bytes_per_second, 1000.0);
    }

    #[test]
    fn totals_skip_loopback() {
        let rates = vec![
            InterfaceRate {
                name: "lo".into(),
                rx_bytes_per_second: 999.0,
                tx_bytes_per_second: 999.0,
                rx_packets_per_second: 0.0,
                tx_packets_per_second: 0.0,
                rx_errors: 0,
                tx_errors: 0,
            },
            InterfaceRate {
                name: "eth0".into(),
                rx_bytes_per_second: 100.0,
                tx_bytes_per_second: 20.0,
                rx_packets_per_second: 0.0,
                tx_packets_per_second: 0.0,
                rx_errors: 0,
                tx_errors: 0,
            },
        ];
        assert_eq!(totals(&rates), (100.0, 20.0));
    }

    #[test]
    fn formats_rates() {
        assert_eq!(format_rate(999.0), "999 B/s");
        assert_eq!(format_rate(1500.0), "1.5 KB/s");
        assert_eq!(format_rate(2_500_000.0), "2.5 MB/s");
    }
}
