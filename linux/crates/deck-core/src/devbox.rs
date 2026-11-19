use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct ListeningPort {
    pub protocol: String,
    pub port: u16,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DockerContainer {
    pub name: String,
    pub image: String,
    pub status: String,
}

/// Parse `/proc/net/tcp` or `tcp6`; state `0A` is LISTEN.
pub fn parse_tcp_table(text: &str, protocol: &str) -> Vec<ListeningPort> {
    text.lines()
        .skip(1)
        .filter_map(|line| {
            let fields: Vec<&str> = line.split_whitespace().collect();
            let local = fields.get(1)?;
            let state = fields.get(3)?;
            if *state != "0A" {
                return None;
            }
            let port_hex = local.rsplit_once(':')?.1;
            let port = u16::from_str_radix(port_hex, 16).ok()?;
            Some(ListeningPort {
                protocol: protocol.to_string(),
                port,
            })
        })
        .collect()
}

/// TCP listeners from the kernel; deduplicated and sorted by port.
pub fn listening_ports() -> io::Result<Vec<ListeningPort>> {
    let mut unique = BTreeSet::new();
    for (path, protocol) in [("/proc/net/tcp", "tcp"), ("/proc/net/tcp6", "tcp6")] {
        if let Ok(text) = fs::read_to_string(path) {
            unique.extend(parse_tcp_table(&text, protocol));
        }
    }
    Ok(unique.into_iter().collect())
}

pub fn parse_docker_ps(text: &str) -> Vec<DockerContainer> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.split('\t');
            let name = fields.next()?.trim();
            let image = fields.next()?.trim();
            let status = fields.next()?.trim();
            if name.is_empty() {
                return None;
            }
            Some(DockerContainer {
                name: name.to_string(),
                image: image.to_string(),
                status: status.to_string(),
            })
        })
        .collect()
}

pub fn docker_containers() -> Vec<DockerContainer> {
    let output = Command::new("docker")
        .args(["ps", "--format", "{{.Names}}\t{{.Image}}\t{{.Status}}"])
        .output();
    let Ok(output) = output else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    parse_docker_ps(&String::from_utf8_lossy(&output.stdout))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_only_listening_tcp_entries() {
        let table = "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n   0: 00000000:0016 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 12345\n   1: 00000000:1F90 00000000:0000 01 00000000:00000000 00:00000000 00000000     0        0 12346\n";
        let ports = parse_tcp_table(table, "tcp");
        assert_eq!(
            ports,
            vec![ListeningPort {
                protocol: "tcp".into(),
                port: 22
            }]
        );
    }

    #[test]
    fn parses_tcp6_ports() {
        let table = "  sl  local_address                         remote_address                        st\n   0: 00000000000000000000000000000000:0016 00000000000000000000000000000000:0000 0A\n";
        assert_eq!(
            parse_tcp_table(table, "tcp6"),
            vec![ListeningPort {
                protocol: "tcp6".into(),
                port: 22
            }]
        );
    }

    #[test]
    fn parses_docker_ps_rows() {
        let rows = parse_docker_ps(
            "api\tnginx:latest\tUp 2 hours\nworker\tapp:v1\tExited (0) 1 hour ago\n",
        );
        assert_eq!(rows.len(), 2);
        assert_eq!(rows[0].name, "api");
        assert_eq!(rows[0].image, "nginx:latest");
        assert_eq!(rows[1].status, "Exited (0) 1 hour ago");
    }
}
