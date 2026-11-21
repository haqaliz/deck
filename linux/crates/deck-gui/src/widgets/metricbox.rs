use std::cell::RefCell;
use std::rc::Rc;

use deck_core::metricbox::{worst_first, MetricBoxSnapshot};
use deck_core::paths::Paths;
use deck_core::settings::{MetricBoxFace, MetricBoxSettings, Settings, WidgetSize};
use deck_core::snapshot;
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets::{self, feed};

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
    paths: Paths,
) -> (gtk::ApplicationWindow, i32) {
    let size = settings.borrow().metricbox.size;
    let feed = feed::build(app, "Metrics", size, (160, 250, 360), settings.clone());
    let body = feed.body.clone();
    let feed_size = feed.size;
    let paths_for_tick = paths.clone();
    let settings_for_tick = settings.clone();
    let tick = move || {
        let metric = settings_for_tick.borrow().metricbox.clone();
        widgets::clear(&body);
        let Some(snapshot) =
            snapshot::read_payload::<MetricBoxSnapshot>(&paths_for_tick, "metricbox")
        else {
            widgets::add_row(&body, &widgets::status_text(&paths_for_tick, "metricbox"));
            return gtk::glib::ControlFlow::Continue;
        };
        let summary = gtk::Box::new(gtk::Orientation::Horizontal, 14);
        for (title, value, color) in [
            ("HOSTS", snapshot.hosts.len().to_string(), widgets::CYAN),
            (
                "FIRING",
                snapshot.firing_alerts.len().to_string(),
                widgets::RED,
            ),
        ] {
            let label = widgets::metric_label(title);
            label.set_markup(&widgets::metric_markup(
                title,
                &value,
                color,
                widgets::WHITE,
            ));
            summary.append(&label);
        }
        body.append(&summary);

        match metric.face {
            MetricBoxFace::Fleet => fleet(&body, &snapshot, &metric, feed_size),
            MetricBoxFace::Host => host(&body, &snapshot, &metric),
            MetricBoxFace::Power => power(&body, &snapshot, &metric),
            MetricBoxFace::Agents => agents(&body, &snapshot),
            MetricBoxFace::Alerts => alerts(&body, &snapshot),
        }

        if let Some(base) = valid_base(&metric.base_url) {
            widgets::link_row(&body, "Open Grafana", &base);
        }
        if let Some(note) = &snapshot.note {
            widgets::add_row(&body, note);
        }
        gtk::glib::ControlFlow::Continue
    };

    tick();
    gtk::glib::timeout_add_seconds_local(5, tick);
    (feed.window, feed.height)
}

fn fleet(
    body: &gtk::Box,
    snapshot: &MetricBoxSnapshot,
    settings: &MetricBoxSettings,
    size: WidgetSize,
) {
    widgets::section(body, "FLEET");
    let limit = match size {
        WidgetSize::Small => 3,
        WidgetSize::Medium => 5,
        WidgetSize::Large => 12,
    };
    let hosts = worst_first(&snapshot.hosts);
    for host in hosts.iter().take(limit) {
        let (_, _, value) = widgets::split_row(body, &host.host);
        let mut parts = Vec::new();
        if settings.show_cpu {
            parts.push(format!("C{:.0}", host.cpu.unwrap_or(0.0)));
        }
        if settings.show_ram {
            parts.push(format!("R{:.0}", host.ram.unwrap_or(0.0)));
        }
        if size != WidgetSize::Small {
            if settings.show_disk {
                parts.push(format!("D{:.0}", host.disk.unwrap_or(0.0)));
            }
            if settings.show_gpu {
                if let Some(gpu) = host.gpu_percent {
                    parts.push(format!("G{gpu:.0}"));
                }
            }
            if settings.show_power {
                if let Some(watts) = host.total_watts() {
                    parts.push(format!("{watts:.0}W"));
                }
            }
        }
        let color = if host.last_seen_seconds.unwrap_or(0.0) > 120.0 {
            widgets::RED
        } else {
            "#8e8e93"
        };
        value.set_markup(&format!(
            "<span foreground=\"{color}\">{}</span>",
            parts.join("  ")
        ));
    }
    if snapshot.hosts.is_empty() {
        widgets::add_row(body, "No hosts returned");
    }
}

fn host(body: &gtk::Box, snapshot: &MetricBoxSnapshot, settings: &MetricBoxSettings) {
    let Some(host) = snapshot
        .hosts
        .iter()
        .find(|host| host.host == settings.host.trim())
        .or_else(|| snapshot.hosts.first())
    else {
        widgets::add_row(body, "Set a host in Settings");
        return;
    };
    widgets::section(body, "HOST");
    for (label, value) in [
        ("CPU", host.cpu),
        ("RAM", host.ram),
        ("DISK", host.disk),
        ("GPU", host.gpu_percent),
        ("VRAM", host.vram_percent),
        ("TEMP", host.gpu_temperature),
    ] {
        if let Some(value) = value {
            widgets::add_row(body, &format!("{label}   {value:.0}%"));
        }
    }
    if !snapshot.trend_cpu.is_empty() {
        let chart = gtk::DrawingArea::new();
        chart.set_size_request(-1, 40);
        let values: Vec<i64> = snapshot
            .trend_cpu
            .iter()
            .map(|value| value.round() as i64)
            .collect();
        chart.set_draw_func(move |_, cr, width, height| {
            widgets::draw_bars(cr, width, height, &values, false);
        });
        body.append(&chart);
    }
}

fn power(body: &gtk::Box, snapshot: &MetricBoxSnapshot, settings: &MetricBoxSettings) {
    widgets::section(body, "POWER");
    let rate = settings.rate_per_kwh_cents as f64 / 100.0;
    for host in &snapshot.hosts {
        let Some(watts) = host.total_watts() else {
            continue;
        };
        let monthly = host.kwh_24h.map(|kwh| kwh * 30.0 * rate);
        let cost = monthly
            .map(|value| format!("   ${value:.0}/mo"))
            .unwrap_or_default();
        widgets::add_row(body, &format!("{}   {watts:.0} W{cost}", host.host));
    }
}

fn agents(body: &gtk::Box, snapshot: &MetricBoxSnapshot) {
    widgets::section(body, "AGENTS");
    for agent in snapshot.agents.iter().take(6) {
        widgets::add_row(
            body,
            &format!(
                "{}/{}   {:.0}%   {:.0} MB",
                agent.host,
                agent.name,
                agent.cpu.unwrap_or(0.0),
                agent.ram.unwrap_or(0.0) / 1_048_576.0
            ),
        );
    }
    if snapshot.agents.is_empty() {
        widgets::add_row(body, "No container metrics");
    }
}

fn alerts(body: &gtk::Box, snapshot: &MetricBoxSnapshot) {
    widgets::section(body, "ALERTS");
    for alert in &snapshot.firing_alerts {
        let row = widgets::add_row(
            body,
            &format!("{}   {}   {}", alert.name, alert.severity, alert.host),
        );
        if alert.severity.eq_ignore_ascii_case("critical") {
            row.add_css_class("alarm");
        }
        if !alert.summary.is_empty() {
            widgets::add_row(body, &alert.summary);
        }
    }
    if snapshot.firing_alerts.is_empty() {
        widgets::add_row(body, "Nothing firing");
    }
}

fn valid_base(base: &str) -> Option<String> {
    let base = base.trim().trim_end_matches('/');
    (base.starts_with("https://") || base.starts_with("http://")).then(|| base.to_owned())
}
