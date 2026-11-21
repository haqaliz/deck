use std::cell::{Cell, RefCell};
use std::collections::VecDeque;
use std::path::Path;
use std::rc::Rc;

use deck_core::livebox::{
    disk_usage, disk_volumes, gpu_usage, memory_info, memory_usage, tier, CpuSampler, DiskVolume,
    ProcessSample, ProcessSampler,
};
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

const COLORS: [(f64, f64, f64); 3] = [(0.42, 0.78, 0.35), (0.0, 0.75, 0.91), (1.0, 0.55, 0.16)];

#[derive(Clone, Copy, PartialEq, Eq)]
enum ProcessMode {
    Cpu,
    Mem,
}

pub fn build(
    app: &gtk::Application,
    settings: Rc<RefCell<Settings>>,
) -> (gtk::ApplicationWindow, i32) {
    let (size, show_chart, show_processes, refresh_seconds) = {
        let livebox = &settings.borrow().livebox;
        (
            livebox.size,
            livebox.show_chart,
            livebox.show_processes,
            livebox.refresh_seconds,
        )
    };
    let height = widgets::height(size, 160, 220, 360);
    let spec = deck_platform::surface::WidgetSpec {
        width: 320,
        height,
        top: 80,
        left: 80,
        title: "LiveBox".into(),
    };
    let window = deck_platform::surface::widget_window(app, &spec);
    window.add_css_class("deck-surface");

    let content = gtk::Box::new(gtk::Orientation::Vertical, 4);
    content.set_margin_top(12);
    content.set_margin_bottom(12);
    content.set_margin_start(14);
    content.set_margin_end(14);

    content.append(&crate::ui::widget_drag_bar(&window, settings.clone()));

    let metrics = gtk::Box::new(
        if size == WidgetSize::Small {
            gtk::Orientation::Vertical
        } else {
            gtk::Orientation::Horizontal
        },
        12,
    );
    metrics.set_halign(gtk::Align::Start);
    let cpu = widgets::metric_label("CPU");
    let mem = widgets::metric_label("MEM");
    let disk = widgets::metric_label("DISK");
    let gpu = widgets::metric_label("GPU");
    metrics.append(&cpu);
    metrics.append(&mem);
    metrics.append(&disk);
    metrics.append(&gpu);
    content.append(&metrics);

    let chart = (size != WidgetSize::Small && show_chart).then(|| {
        let chart = gtk::DrawingArea::new();
        chart.set_size_request(-1, 62);
        content.append(&chart);
        chart
    });

    let volumes = (size == WidgetSize::Large).then(|| {
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 2);
        content.append(&rows);
        rows
    });

    let process_mode = Rc::new(Cell::new(ProcessMode::Cpu));
    let (processes_header, processes, cpu_tab, mem_tab) =
        if size == WidgetSize::Large && show_processes {
            let header = gtk::Box::new(gtk::Orientation::Horizontal, 6);
            let title = gtk::Label::new(Some("TOP PROCESSES"));
            title.add_css_class("section");
            title.set_halign(gtk::Align::Start);
            title.set_hexpand(true);
            let tabs = gtk::Box::new(gtk::Orientation::Horizontal, 0);
            tabs.add_css_class("process-tabs");
            let cpu_tab = gtk::ToggleButton::with_label("CPU");
            cpu_tab.add_css_class("process-tab");
            cpu_tab.set_active(true);
            let mem_tab = gtk::ToggleButton::with_label("MEM");
            mem_tab.add_css_class("process-tab");
            tabs.append(&cpu_tab);
            tabs.append(&mem_tab);
            header.append(&title);
            header.append(&tabs);
            let divider = gtk::Separator::new(gtk::Orientation::Horizontal);
            divider.add_css_class("widget-divider");
            content.append(&divider);
            let rows = gtk::Box::new(gtk::Orientation::Vertical, 2);
            content.append(&header);
            content.append(&rows);
            (Some(header), Some(rows), Some(cpu_tab), Some(mem_tab))
        } else {
            (None, None, None, None)
        };

    window.set_child(Some(&content));

    let state = Rc::new(RefCell::new(State {
        cpu: CpuSampler::new(),
        processes: ProcessSampler::new(),
        history: VecDeque::new(),
    }));

    if let Some(chart) = &chart {
        let state_for_draw = state.clone();
        chart.set_draw_func(move |_, cr, width, height| {
            let state = state_for_draw.borrow();
            let series: Vec<Vec<f64>> = (0..3)
                .map(|index| widgets::history_series(&state.history, index))
                .collect();
            widgets::draw_chart(cr, width, height, &series, &COLORS, Some(100.0));
        });
    }

    let interval = refresh_seconds.clamp(1, 3600) as u32;

    let state_for_tick = state.clone();
    let settings_for_tick = settings.clone();
    let cpu_for_tick = cpu.clone();
    let mem_for_tick = mem.clone();
    let disk_for_tick = disk.clone();
    let gpu_for_tick = gpu.clone();
    let chart_for_tick = chart.clone();
    let processes_for_tick = processes.clone();
    let processes_header_for_tick = processes_header.clone();
    let volumes_for_tick = volumes.clone();
    let process_mode_for_tick = process_mode.clone();
    let tick = Rc::new(move || {
        let livebox = settings_for_tick.borrow().livebox.clone();

        let (cpu_sample, mem_value, disk_value, gpu_value, mut samples) = {
            let mut state = state_for_tick.borrow_mut();
            let cpu_sample = state.cpu.sample().unwrap_or_default();
            let mem_value = memory_usage().unwrap_or(0.0);
            let disk_value = disk_usage(Path::new("/"))
                .map(|usage| usage.used_percent())
                .unwrap_or(0.0);
            let gpu_value = gpu_usage();
            let samples = if processes_for_tick.is_some() && livebox.show_processes {
                state
                    .processes
                    .sample(livebox.process_count.max(1) as usize)
                    .unwrap_or_default()
            } else {
                Vec::new()
            };
            state
                .history
                .push_back([cpu_sample.overall, mem_value, disk_value]);
            while state.history.len() > 120 {
                state.history.pop_front();
            }
            (cpu_sample, mem_value, disk_value, gpu_value, samples)
        };

        cpu_for_tick.set_visible(livebox.show_cpu);
        mem_for_tick.set_visible(livebox.show_mem);
        disk_for_tick.set_visible(livebox.show_disk);
        gpu_for_tick.set_visible(livebox.show_gpu && gpu_value.is_some());

        update_metric(
            &cpu_for_tick,
            "CPU",
            cpu_sample.overall,
            widgets::GREEN,
            livebox.cpu_warn as f64,
            livebox.cpu_alarm as f64,
        );
        update_metric(
            &mem_for_tick,
            "MEM",
            mem_value,
            widgets::CYAN,
            livebox.mem_warn as f64,
            livebox.mem_alarm as f64,
        );
        update_metric(
            &disk_for_tick,
            "DISK",
            disk_value,
            widgets::ORANGE,
            livebox.disk_warn as f64,
            livebox.disk_alarm as f64,
        );
        if let Some(value) = gpu_value {
            update_metric(
                &gpu_for_tick,
                "GPU",
                value,
                widgets::PURPLE,
                livebox.gpu_warn as f64,
                livebox.gpu_alarm as f64,
            );
        }

        if let Some(rows) = &volumes_for_tick {
            widgets::clear(rows);
            for volume in disk_volumes().into_iter().take(3) {
                add_volume_row(rows, &volume, livebox.disk_warn, livebox.disk_alarm);
            }
        }

        if let Some(rows) = &processes_for_tick {
            widgets::clear(rows);
            let mode = process_mode_for_tick.get();
            if mode == ProcessMode::Mem {
                samples.sort_by(|left, right| right.rss_bytes.cmp(&left.rss_bytes));
            }
            let mem_total = memory_info().map(|info| info.total_kb * 1024).unwrap_or(0);
            for sample in &samples {
                let mem_percent = if mem_total == 0 {
                    0.0
                } else {
                    sample.rss_bytes as f64 / mem_total as f64 * 100.0
                };
                add_process_row(rows, sample, mem_percent, mode);
            }
        }
        if let Some(header) = &processes_header_for_tick {
            header.set_visible(livebox.show_processes);
        }

        if let Some(chart) = &chart_for_tick {
            chart.queue_draw();
        }
    });

    if let (Some(cpu_widget), Some(mem_widget)) = (&cpu_tab, &mem_tab) {
        let cpu = cpu_widget.clone();
        let mem = mem_widget.clone();
        let mode = process_mode.clone();
        let refresh = tick.clone();
        let mem_for_cpu = mem.clone();
        cpu.connect_clicked(move |button| {
            if !button.is_active() {
                button.set_active(true);
                return;
            }
            mem_for_cpu.set_active(false);
            mode.set(ProcessMode::Cpu);
            refresh();
        });
        let mode = process_mode.clone();
        let refresh = tick.clone();
        let cpu_for_mem = cpu.clone();
        mem.connect_clicked(move |button| {
            if !button.is_active() {
                button.set_active(true);
                return;
            }
            cpu_for_mem.set_active(false);
            mode.set(ProcessMode::Mem);
            refresh();
        });
    }

    // One early sample gives the first frame a real delta instead of 0%.
    let tick_once = tick.clone();
    gtk::glib::timeout_add_seconds_local_once(1, move || tick_once());
    let tick_for_timeout = tick;
    gtk::glib::timeout_add_seconds_local(interval, move || {
        tick_for_timeout();
        gtk::glib::ControlFlow::Continue
    });

    (window, height)
}

#[derive(Default)]
struct State {
    cpu: CpuSampler,
    processes: ProcessSampler,
    history: VecDeque<[f64; 3]>,
}

fn add_volume_row(container: &gtk::Box, volume: &DiskVolume, warn: u8, alarm: u8) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 6);
    let dot = gtk::Label::new(None);
    let color = if tier(volume.used_percent, warn as f64, alarm as f64)
        == deck_core::livebox::Tier::Alarm
    {
        widgets::RED
    } else {
        widgets::ORANGE
    };
    dot.set_markup(&format!("<span foreground=\"{color}\">●</span>"));
    let name = gtk::Label::new(Some(&volume.mount));
    name.add_css_class("row-name");
    name.set_xalign(0.0);
    name.set_hexpand(true);
    name.set_ellipsize(gtk::pango::EllipsizeMode::End);
    let percent = gtk::Label::new(Some(&format!("{:3.0}%", volume.used_percent)));
    percent.add_css_class("row-value");
    percent.set_xalign(1.0);
    percent.set_width_chars(4);
    let free = gtk::Label::new(Some(&format_free_bytes(volume.available_bytes)));
    free.add_css_class("row-muted");
    free.set_xalign(1.0);
    row.append(&dot);
    row.append(&name);
    row.append(&percent);
    row.append(&free);
    container.append(&row);
}

fn add_process_row(
    container: &gtk::Box,
    sample: &ProcessSample,
    mem_percent: f64,
    mode: ProcessMode,
) {
    let row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let name = gtk::Label::new(Some(&sample.name));
    name.add_css_class("row-name");
    name.set_xalign(0.0);
    name.set_hexpand(true);
    name.set_ellipsize(gtk::pango::EllipsizeMode::End);
    let cpu_color = if mode == ProcessMode::Cpu {
        widgets::GREEN
    } else {
        "#6e6e73"
    };
    let mem_color = if mode == ProcessMode::Mem {
        widgets::CYAN
    } else {
        "#6e6e73"
    };
    let cpu = gtk::Label::new(None);
    cpu.set_markup(&format!(
        "<span foreground=\"{cpu_color}\">{:.1}%</span>",
        sample.cpu_percent
    ));
    cpu.add_css_class("row-value");
    cpu.set_xalign(1.0);
    cpu.set_width_chars(5);
    let mem = gtk::Label::new(None);
    mem.set_markup(&format!(
        "<span foreground=\"{mem_color}\">{mem_percent:.1}%</span>"
    ));
    mem.add_css_class("row-value");
    mem.set_xalign(1.0);
    mem.set_width_chars(5);
    row.append(&name);
    row.append(&cpu);
    row.append(&mem);
    container.append(&row);
}

/// Decimal units, as the macOS face shows them ("195 GB free").
fn format_free_bytes(bytes: u64) -> String {
    let value = bytes as f64;
    if value >= 1_000_000_000_000.0 {
        format!("{:.1} TB free", value / 1_000_000_000_000.0)
    } else if value >= 1_000_000_000.0 {
        format!("{:.0} GB free", value / 1_000_000_000.0)
    } else if value >= 1_000_000.0 {
        format!("{:.0} MB free", value / 1_000_000.0)
    } else if value >= 1_000.0 {
        format!("{:.0} KB free", value / 1_000.0)
    } else {
        format!("{bytes} B free")
    }
}

fn update_metric(label: &gtk::Label, title: &str, value: f64, dot: &str, warn: f64, alarm: f64) {
    let level = tier(value, warn, alarm);
    label.set_markup(&widgets::metric_markup(
        title,
        &format!("{value:>3.0}%"),
        dot,
        widgets::value_color(level),
    ));
}

#[cfg(test)]
mod tests {
    use super::format_free_bytes;

    #[test]
    fn free_space_uses_decimal_units() {
        assert_eq!(format_free_bytes(512_000_000), "512 MB free");
        assert_eq!(format_free_bytes(195_000_000_000), "195 GB free");
        assert_eq!(format_free_bytes(1_200_000_000_000), "1.2 TB free");
    }
}
