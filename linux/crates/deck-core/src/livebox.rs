use std::collections::HashMap;
use std::ffi::CString;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;
use std::thread;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct CpuTicks {
    pub user: u64,
    pub nice: u64,
    pub system: u64,
    pub idle: u64,
    pub iowait: u64,
    pub irq: u64,
    pub softirq: u64,
    pub steal: u64,
}

impl CpuTicks {
    pub fn total(self) -> u64 {
        self.user
            + self.nice
            + self.system
            + self.idle
            + self.iowait
            + self.irq
            + self.softirq
            + self.steal
    }

    pub fn idle_total(self) -> u64 {
        self.idle + self.iowait
    }

    fn parse_line(line: &str) -> Option<(String, Self)> {
        let mut parts = line.split_whitespace();
        let label = parts.next()?.to_string();
        if !label.starts_with("cpu") {
            return None;
        }
        let mut values = [0_u64; 8];
        for value in &mut values {
            *value = parts.next()?.parse().ok()?;
        }
        Some((
            label,
            Self {
                user: values[0],
                nice: values[1],
                system: values[2],
                idle: values[3],
                iowait: values[4],
                irq: values[5],
                softirq: values[6],
                steal: values[7],
            },
        ))
    }
}

/// Parse `/proc/stat` CPU lines. The first is the aggregate; the rest are cores.
pub fn parse_proc_stat(text: &str) -> Vec<(String, CpuTicks)> {
    text.lines().filter_map(CpuTicks::parse_line).collect()
}

pub fn cpu_usage(previous: CpuTicks, current: CpuTicks) -> f64 {
    let total = current.total().saturating_sub(previous.total());
    if total == 0 {
        return 0.0;
    }
    let idle = current.idle_total().saturating_sub(previous.idle_total());
    ((total.saturating_sub(idle)) as f64 / total as f64 * 100.0).clamp(0.0, 100.0)
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CpuSample {
    pub overall: f64,
    pub cores: Vec<f64>,
}

#[derive(Debug, Default)]
pub struct CpuSampler {
    previous: Option<Vec<CpuTicks>>,
}

impl CpuSampler {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn sample(&mut self) -> io::Result<CpuSample> {
        let text = fs::read_to_string("/proc/stat")?;
        let current: Vec<CpuTicks> = parse_proc_stat(&text)
            .into_iter()
            .map(|(_, ticks)| ticks)
            .collect();
        if current.is_empty() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                "no cpu lines in /proc/stat",
            ));
        }
        let sample = match &self.previous {
            Some(previous) if previous.len() == current.len() => CpuSample {
                overall: cpu_usage(previous[0], current[0]),
                cores: previous
                    .iter()
                    .skip(1)
                    .zip(current.iter().skip(1))
                    .map(|(previous, current)| cpu_usage(*previous, *current))
                    .collect(),
            },
            _ => CpuSample {
                overall: 0.0,
                cores: vec![0.0; current.len() - 1],
            },
        };
        self.previous = Some(current);
        Ok(sample)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Tier {
    Normal,
    Warn,
    Alarm,
}

/// Threshold table shared by every system widget.
pub fn tier(value: f64, warn: f64, alarm: f64) -> Tier {
    if value >= alarm {
        Tier::Alarm
    } else if value >= warn {
        Tier::Warn
    } else {
        Tier::Normal
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MemInfo {
    pub total_kb: u64,
    pub available_kb: u64,
}

impl MemInfo {
    pub fn used_percent(self) -> f64 {
        if self.total_kb == 0 {
            return 0.0;
        }
        (self.total_kb.saturating_sub(self.available_kb)) as f64 / self.total_kb as f64 * 100.0
    }
}

pub fn parse_meminfo(text: &str) -> Option<MemInfo> {
    let mut total = None;
    let mut available = None;
    for line in text.lines() {
        let Some((key, rest)) = line.split_once(':') else {
            continue;
        };
        let Some(value) = rest
            .split_whitespace()
            .next()
            .and_then(|value| value.parse::<u64>().ok())
        else {
            continue;
        };
        match key {
            "MemTotal" => total = Some(value),
            "MemAvailable" => available = Some(value),
            _ => {}
        }
    }
    Some(MemInfo {
        total_kb: total?,
        available_kb: available?,
    })
}

pub fn memory_info() -> io::Result<MemInfo> {
    let text = fs::read_to_string("/proc/meminfo")?;
    parse_meminfo(&text)
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidData, "no MemTotal/MemAvailable"))
}

pub fn memory_usage() -> io::Result<f64> {
    memory_info().map(MemInfo::used_percent)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiskUsage {
    pub total_bytes: u64,
    pub available_bytes: u64,
}

impl DiskUsage {
    pub fn used_percent(self) -> f64 {
        if self.total_bytes == 0 {
            return 0.0;
        }
        (self.total_bytes.saturating_sub(self.available_bytes)) as f64 / self.total_bytes as f64
            * 100.0
    }
}

pub fn disk_usage(path: &Path) -> io::Result<DiskUsage> {
    let path = CString::new(path.as_os_str().as_encoded_bytes())
        .map_err(|_| io::Error::new(io::ErrorKind::InvalidInput, "path contains NUL"))?;
    let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
    let result = unsafe { libc::statvfs(path.as_ptr(), stat.as_mut_ptr()) };
    if result != 0 {
        return Err(io::Error::last_os_error());
    }
    let stat = unsafe { stat.assume_init() };
    Ok(DiskUsage {
        total_bytes: stat.f_blocks * stat.f_frsize,
        available_bytes: stat.f_bavail * stat.f_frsize,
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct DiskVolume {
    pub mount: String,
    pub used_percent: f64,
    pub available_bytes: u64,
}

/// Device, mount point and filesystem type from `/proc/mounts`.
pub fn parse_mounts(text: &str) -> Vec<(String, String, String)> {
    text.lines()
        .filter_map(|line| {
            let mut fields = line.split_whitespace();
            let device = fields.next()?.to_string();
            let mount = fields.next()?.to_string();
            let fs = fields.next()?.to_string();
            Some((device, mount, fs))
        })
        .collect()
}

fn is_real_filesystem(fs: &str) -> bool {
    matches!(
        fs,
        "ext2"
            | "ext3"
            | "ext4"
            | "btrfs"
            | "xfs"
            | "f2fs"
            | "vfat"
            | "exfat"
            | "ntfs"
            | "ntfs3"
            | "zfs"
    )
}

/// Mounted local filesystems with their usage. Pseudo filesystems are skipped.
pub fn disk_volumes() -> Vec<DiskVolume> {
    let text = fs::read_to_string("/proc/mounts").unwrap_or_default();
    let mut volumes = Vec::new();
    for (_, mount, fs) in parse_mounts(&text) {
        if !is_real_filesystem(&fs) {
            continue;
        }
        let Ok(usage) = disk_usage(Path::new(&mount)) else {
            continue;
        };
        if usage.total_bytes == 0 {
            continue;
        }
        volumes.push(DiskVolume {
            mount,
            used_percent: usage.used_percent(),
            available_bytes: usage.available_bytes,
        });
    }
    volumes.sort_by(|left, right| left.mount.cmp(&right.mount));
    volumes.dedup_by(|left, right| left.mount == right.mount);
    volumes
}

/// Returns the first vendor backend that answers; nil means "hide the row".
pub fn gpu_usage() -> Option<f64> {
    amd_gpu_usage().or_else(nvidia_gpu_usage)
}

fn amd_gpu_usage() -> Option<f64> {
    let entries = fs::read_dir("/sys/class/drm").ok()?;
    for entry in entries.flatten() {
        let name = entry.file_name();
        if !name.to_string_lossy().starts_with("card") {
            continue;
        }
        let path = entry.path().join("device/gpu_busy_percent");
        if let Ok(text) = fs::read_to_string(path) {
            if let Ok(value) = text.trim().parse::<f64>() {
                return Some(value.clamp(0.0, 100.0));
            }
        }
    }
    None
}

fn nvidia_gpu_usage() -> Option<f64> {
    let output = Command::new("nvidia-smi")
        .args([
            "--query-gpu=utilization.gpu",
            "--format=csv,noheader,nounits",
        ])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }
    String::from_utf8_lossy(&output.stdout)
        .lines()
        .next()?
        .trim()
        .parse::<f64>()
        .ok()
        .map(|value| value.clamp(0.0, 100.0))
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessSample {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f64,
    pub rss_bytes: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ParsedStat {
    pid: u32,
    name: String,
    ticks: u64,
    rss_pages: u64,
}

fn parse_stat_line(text: &str) -> Option<ParsedStat> {
    let open = text.find('(')?;
    let close = text.rfind(") ")?;
    if close <= open {
        return None;
    }
    let pid = text[..open].trim().parse::<u32>().ok()?;
    let name = text[open + 1..close].to_string();
    let fields: Vec<&str> = text[close + 2..].split_whitespace().collect();
    let utime = fields.get(11)?.parse::<u64>().ok()?;
    let stime = fields.get(12)?.parse::<u64>().ok()?;
    let rss = fields.get(21)?.parse::<i64>().ok()?.max(0) as u64;
    Some(ParsedStat {
        pid,
        name,
        ticks: utime + stime,
        rss_pages: rss,
    })
}

#[derive(Debug)]
pub struct ProcessSampler {
    previous_total: Option<u64>,
    previous: HashMap<u32, u64>,
    cpu_count: usize,
    page_size: u64,
}

impl Default for ProcessSampler {
    fn default() -> Self {
        Self::new()
    }
}

impl ProcessSampler {
    pub fn new() -> Self {
        let cpu_count = thread::available_parallelism()
            .map(|count| count.get())
            .unwrap_or(1);
        let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) }.max(1) as u64;
        Self {
            previous_total: None,
            previous: HashMap::new(),
            cpu_count,
            page_size,
        }
    }

    pub fn sample(&mut self, limit: usize) -> io::Result<Vec<ProcessSample>> {
        let stat_text = fs::read_to_string("/proc/stat")?;
        let total = parse_proc_stat(&stat_text)
            .into_iter()
            .find(|(label, _)| label == "cpu")
            .map(|(_, ticks)| ticks.total())
            .unwrap_or(0);
        let total_delta = self
            .previous_total
            .map(|previous| total.saturating_sub(previous))
            .unwrap_or(0);

        let mut samples = Vec::new();
        let mut current_ticks = HashMap::new();
        for entry in fs::read_dir("/proc")?.flatten() {
            let name = entry.file_name();
            let Ok(pid) = name.to_string_lossy().parse::<u32>() else {
                continue;
            };
            let Ok(text) = fs::read_to_string(entry.path().join("stat")) else {
                continue;
            };
            let Some(stat) = parse_stat_line(&text) else {
                continue;
            };
            current_ticks.insert(pid, stat.ticks);
            let previous = self.previous.get(&pid).copied().unwrap_or(stat.ticks);
            let delta = stat.ticks.saturating_sub(previous);
            let cpu_percent = if total_delta == 0 {
                0.0
            } else {
                delta as f64 / total_delta as f64 * 100.0 * self.cpu_count as f64
            };
            samples.push(ProcessSample {
                pid: stat.pid,
                name: stat.name,
                cpu_percent,
                rss_bytes: stat.rss_pages * self.page_size,
            });
        }

        self.previous_total = Some(total);
        self.previous = current_ticks;

        // comm is truncated to 15 bytes; the executable's basename is the
        // name a user recognizes ("x-terminal-emulator", not "x-terminal-emul").
        for sample in &mut samples {
            if let Ok(cmdline) = fs::read(format!("/proc/{}/cmdline", sample.pid)) {
                if let Some(name) = argv0_name(&cmdline) {
                    sample.name = name;
                }
            }
        }

        samples.sort_by(|left, right| {
            right
                .cpu_percent
                .partial_cmp(&left.cpu_percent)
                .unwrap_or(std::cmp::Ordering::Equal)
                .then_with(|| right.rss_bytes.cmp(&left.rss_bytes))
        });
        samples.truncate(limit);
        Ok(samples)
    }
}

fn argv0_name(cmdline: &[u8]) -> Option<String> {
    let arg0 = cmdline.split(|byte| *byte == 0).next()?;
    let path = std::str::from_utf8(arg0).ok()?;
    let name = Path::new(path).file_name()?.to_string_lossy().into_owned();
    (!name.is_empty()).then_some(name)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_cpu_lines_and_computes_usage() {
        let text = "cpu 10 0 20 70 0 0 0 0\ncpu0 5 0 10 35 0 0 0 0\n";
        let parsed = parse_proc_stat(text);
        assert_eq!(parsed.len(), 2);
        assert_eq!(parsed[0].0, "cpu");
        assert_eq!(parsed[0].1.total(), 100);
        assert_eq!(parsed[0].1.idle_total(), 70);
        assert_eq!(
            cpu_usage(
                parsed[0].1,
                CpuTicks {
                    user: 30,
                    system: 30,
                    idle: 140,
                    ..Default::default()
                }
            ),
            30.0
        );
    }

    #[test]
    fn parses_memory_and_percent() {
        let info = parse_meminfo("MemTotal: 1000 kB\nMemAvailable: 250 kB\n").expect("meminfo");
        assert_eq!(
            info,
            MemInfo {
                total_kb: 1000,
                available_kb: 250
            }
        );
        assert_eq!(info.used_percent(), 75.0);
    }

    #[test]
    fn parses_a_proc_stat_line() {
        let line = "123 (test) S 1 1 1 0 -1 4194560 100 0 0 0 10 20 0 0 20 0 1 0 100 1000 50 18446744073709551615 0";
        let parsed = parse_stat_line(line).expect("stat");
        assert_eq!(parsed.pid, 123);
        assert_eq!(parsed.name, "test");
        assert_eq!(parsed.ticks, 30);
        assert_eq!(parsed.rss_pages, 50);
    }

    #[test]
    fn parses_mounts_and_skips_pseudo_filesystems() {
        let text = "/dev/mmcblk0p2 / ext4 rw,relatime 0 0\nproc /proc proc rw 0 0\n/dev/mmcblk0p1 /boot/firmware vfat rw 0 0\n";
        let mounts = parse_mounts(text);
        assert_eq!(mounts.len(), 3);
        assert_eq!(mounts[0].0, "/dev/mmcblk0p2");
        assert_eq!(mounts[0].1, "/");
        assert_eq!(mounts[0].2, "ext4");
        assert_eq!(mounts[2].2, "vfat");
        assert!(is_real_filesystem("ext4"));
        assert!(is_real_filesystem("vfat"));
        assert!(!is_real_filesystem("proc"));
    }

    #[test]
    fn tiers_use_warn_and_alarm_boundaries() {
        assert_eq!(tier(79.9, 80.0, 90.0), Tier::Normal);
        assert_eq!(tier(80.0, 80.0, 90.0), Tier::Warn);
        assert_eq!(tier(89.9, 80.0, 90.0), Tier::Warn);
        assert_eq!(tier(90.0, 80.0, 90.0), Tier::Alarm);
    }

    #[test]
    fn takes_the_basename_from_argv0() {
        assert_eq!(argv0_name(b"/usr/bin/htop\0"), Some("htop".into()));
        assert_eq!(
            argv0_name(b"./target/debug/deck-gui\0--toggle-search\0"),
            Some("deck-gui".into())
        );
        assert_eq!(argv0_name(b""), None);
    }

    #[test]
    fn root_disk_is_readable() {
        let usage = disk_usage(Path::new("/")).expect("root disk");
        assert!(usage.total_bytes > 0);
        assert!(usage.available_bytes <= usage.total_bytes);
    }
}
