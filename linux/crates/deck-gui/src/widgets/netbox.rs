use std::cell::RefCell;
use std::collections::VecDeque;
use std::rc::Rc;

use deck_core::livebox::tier;
use deck_core::netbox::{format_rate, totals, NetSampler};
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

const COLORS: [(f64, f64, f64); 2] = [(0.0, 0.75, 0.91), (0.42, 0.78, 0.35)];

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, i32) {
    let (size, show_chart, refresh_seconds) = {
        let netbox = &settings.borrow().netbox;
        (netbox.size, netbox.show_chart, netbox.refresh_seconds)
    };
    let height = widgets::height(size, 120, 230, 300);
    let spec = deck_platform::surface::WidgetSpec {
        width: 320,
        height,
        top: 80,
        left: 460,
        title: "NetBox".into(),
    };
    let window = deck_platform::surface::widget_window(app, &spec);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.set_margin_top(12);
    content.set_margin_bottom(12);
    content.set_margin_start(14);
    content.set_margin_end(14);

    content.append(&crate::ui::widget_drag_bar(&window, settings.clone()));

    let summary = gtk::Box::new(
        if size == WidgetSize::Small {
            gtk::Orientation::Vertical
        } else {
            gtk::Orientation::Horizontal
        },
        14,
    );
    summary.set_halign(gtk::Align::Start);
    let down = widgets::metric_label("DOWN");
    let up = widgets::metric_label("UP");
    summary.append(&down);
    summary.append(&up);
    let active = (size == WidgetSize::Small).then(|| {
        let label = gtk::Label::new(None);
        label.add_css_class("metric");
        label.set_halign(gtk::Align::Start);
        label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        summary.append(&label);
        label
    });
    content.append(&summary);

    let chart = (size == WidgetSize::Large && show_chart).then(|| {
        let chart = gtk::DrawingArea::new();
        chart.set_size_request(-1, 60);
        content.append(&chart);
        chart
    });

    let interfaces = (size != WidgetSize::Small).then(|| {
        widgets::section(&content, "INTERFACES");
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 2);
        content.append(&rows);
        rows
    });

    window.set_child(Some(&content));

    let state = Rc::new(RefCell::new(State {
        sampler: NetSampler::new(),
        history: VecDeque::new(),
    }));

    if let Some(chart) = &chart {
        let state_for_draw = state.clone();
        chart.set_draw_func(move |_, cr, width, height| {
            let state = state_for_draw.borrow();
            let series: Vec<Vec<f64>> = (0..2)
                .map(|index| widgets::history_series(&state.history, index))
                .collect();
            widgets::draw_chart(cr, width, height, &series, &COLORS, None);
        });
    }

    let interval = refresh_seconds.clamp(1, 3600) as u32;

    let state_for_tick = state.clone();
    let settings_for_tick = settings.clone();
    let down_for_tick = down.clone();
    let up_for_tick = up.clone();
    let active_for_tick = active.clone();
    let chart_for_tick = chart.clone();
    let interfaces_for_tick = interfaces.clone();
    let tick = move || {
        let netbox = settings_for_tick.borrow().netbox.clone();
        let rates = state_for_tick
            .borrow_mut()
            .sampler
            .sample()
            .unwrap_or_default();
        let (down_value, up_value) = totals(&rates);

        {
            let mut state = state_for_tick.borrow_mut();
            state.history.push_back([down_value, up_value]);
            while state.history.len() > 120 {
                state.history.pop_front();
            }
        }

        down_for_tick.set_markup(&widgets::metric_markup(
            "DOWN",
            &format_rate(down_value),
            widgets::CYAN,
            widgets::WHITE,
        ));
        up_for_tick.set_markup(&widgets::metric_markup(
            "UP",
            &format_rate(up_value),
            widgets::GREEN,
            widgets::WHITE,
        ));

        let visible: Vec<_> = rates
            .iter()
            .filter(|rate| netbox.interface.is_empty() || rate.name == netbox.interface)
            .collect();

        if let Some(label) = &active_for_tick {
            let name = visible
                .iter()
                .find(|rate| rate.name != "lo")
                .or_else(|| visible.first())
                .map(|rate| rate.name.as_str())
                .unwrap_or("—");
            label.set_markup(&widgets::metric_markup(
                "ACTIVE",
                name,
                widgets::GREEN,
                widgets::WHITE,
            ));
        }

        if let Some(rows) = &interfaces_for_tick {
            widgets::clear(rows);
            if visible.is_empty() {
                widgets::add_row(rows, "Warming up…");
            } else {
                for rate in visible.iter().take(netbox.interface_count.max(1) as usize) {
                    let (_, _, value) = widgets::split_row(rows, &rate.name);
                    let up_mbps = rate.tx_bytes_per_second / 1_000_000.0;
                    let down_mbps = rate.rx_bytes_per_second / 1_000_000.0;
                    let mut right = format!(
                        "<span foreground=\"{}\">↑ {}</span>   <span foreground=\"{}\">↓ {}</span>",
                        rate_color(up_mbps, netbox.warn_mbps, netbox.alarm_mbps, widgets::GREEN),
                        format_rate(rate.tx_bytes_per_second),
                        rate_color(
                            down_mbps,
                            netbox.warn_mbps,
                            netbox.alarm_mbps,
                            widgets::CYAN
                        ),
                        format_rate(rate.rx_bytes_per_second)
                    );
                    if netbox.show_packets {
                        right.push_str(&format!(
                            "   <span foreground=\"#8e8e93\">{:.0}/{:.0} pkt/s</span>",
                            rate.rx_packets_per_second, rate.tx_packets_per_second
                        ));
                    }
                    if rate.rx_errors + rate.tx_errors > 0 {
                        right.push_str(&format!(
                            "   <span foreground=\"{}\">err {}/{}</span>",
                            widgets::RED,
                            rate.rx_errors,
                            rate.tx_errors
                        ));
                    }
                    value.set_markup(&right);
                }
            }
        }

        if let Some(chart) = &chart_for_tick {
            chart.queue_draw();
        }
        gtk::glib::ControlFlow::Continue
    };

    let tick_once = tick.clone();
    gtk::glib::timeout_add_seconds_local_once(1, move || {
        tick_once();
    });
    gtk::glib::timeout_add_seconds_local(interval, tick);
    (window, height)
}

struct State {
    sampler: NetSampler,
    history: VecDeque<[f64; 2]>,
}

fn rate_color(mbps: f64, warn: u16, alarm: u16, normal: &'static str) -> &'static str {
    match tier(mbps, warn as f64, alarm as f64) {
        deck_core::livebox::Tier::Normal => normal,
        deck_core::livebox::Tier::Warn => widgets::ORANGE,
        deck_core::livebox::Tier::Alarm => widgets::RED,
    }
}
