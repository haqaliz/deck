use std::cell::RefCell;
use std::collections::VecDeque;
use std::path::Path;
use std::rc::Rc;

use deck_core::livebox::{
    disk_usage, disk_volumes, gpu_usage, memory_usage, tier, CpuSampler, ProcessSampler,
};
use deck_core::settings::{Settings, WidgetSize};
use gtk4 as gtk;
use gtk4::prelude::*;

use crate::widgets;

const COLORS: [(f64, f64, f64); 3] = [(0.42, 0.78, 0.35), (0.0, 0.75, 0.91), (1.0, 0.55, 0.16)];

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

    let header = gtk::Label::new(Some("LIVEBOX"));
    header.add_css_class("subtitle");
    header.set_halign(gtk::Align::Start);
    content.append(&header);

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
        chart.set_size_request(-1, 46);
        content.append(&chart);
        chart
    });

    let cores = (size == WidgetSize::Large).then(|| {
        let label = gtk::Label::new(Some("CORES   —"));
        label.add_css_class("subtitle");
        label.set_halign(gtk::Align::Start);
        label.set_ellipsize(gtk::pango::EllipsizeMode::End);
        content.append(&label);
        label
    });

    let (processes_header, processes) = if size == WidgetSize::Large && show_processes {
        let header = gtk::Label::new(Some("PROCESSES"));
        header.add_css_class("section");
        header.set_halign(gtk::Align::Start);
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 1);
        content.append(&header);
        content.append(&rows);
        (Some(header), Some(rows))
    } else {
        (None, None)
    };

    let volumes = (size == WidgetSize::Large).then(|| {
        let header = gtk::Label::new(Some("VOLUMES"));
        header.add_css_class("section");
        header.set_halign(gtk::Align::Start);
        let rows = gtk::Box::new(gtk::Orientation::Vertical, 1);
        content.append(&header);
        content.append(&rows);
        rows
    });

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
    let cores_for_tick = cores.clone();
    let processes_for_tick = processes.clone();
    let processes_header_for_tick = processes_header.clone();
    let volumes_for_tick = volumes.clone();
    let tick = move || {
        let livebox = settings_for_tick.borrow().livebox.clone();

        let (cpu_sample, mem_value, disk_value, gpu_value, samples) = {
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
            livebox.cpu_warn as f64,
            livebox.cpu_alarm as f64,
        );
        update_metric(
            &mem_for_tick,
            "MEM",
            mem_value,
            livebox.mem_warn as f64,
            livebox.mem_alarm as f64,
        );
        update_metric(
            &disk_for_tick,
            "DISK",
            disk_value,
            livebox.disk_warn as f64,
            livebox.disk_alarm as f64,
        );
        if let Some(value) = gpu_value {
            update_metric(
                &gpu_for_tick,
                "GPU",
                value,
                livebox.gpu_warn as f64,
                livebox.gpu_alarm as f64,
            );
        }

        if let Some(label) = &cores_for_tick {
            let text = cpu_sample
                .cores
                .iter()
                .enumerate()
                .map(|(index, value)| format!("{index} {value:.0}%"))
                .collect::<Vec<_>>()
                .join("   ");
            label.set_text(&format!("CORES   {text}"));
        }

        if let Some(rows) = &processes_for_tick {
            widgets::clear(rows);
            for sample in samples {
                widgets::add_row(
                    rows,
                    &format!(
                        "{}  {:.0}%  {:.0} MB",
                        sample.name,
                        sample.cpu_percent,
                        sample.rss_bytes as f64 / 1_048_576.0
                    ),
                );
            }
        }
        if let Some(header) = &processes_header_for_tick {
            header.set_visible(livebox.show_processes);
        }

        if let Some(rows) = &volumes_for_tick {
            widgets::clear(rows);
            for volume in disk_volumes().into_iter().take(3) {
                let row = widgets::add_row(
                    rows,
                    &format!("{}  {:.0}%", volume.mount, volume.used_percent),
                );
                widgets::apply_tier(
                    &row,
                    tier(
                        volume.used_percent,
                        livebox.disk_warn as f64,
                        livebox.disk_alarm as f64,
                    ),
                );
            }
        }

        if let Some(chart) = &chart_for_tick {
            chart.queue_draw();
        }
        gtk::glib::ControlFlow::Continue
    };

    // One early sample gives the first frame a real delta instead of 0%.
    let tick_once = tick.clone();
    gtk::glib::timeout_add_seconds_local_once(1, move || {
        tick_once();
    });
    gtk::glib::timeout_add_seconds_local(interval, tick);

    (window, height)
}

#[derive(Default)]
struct State {
    cpu: CpuSampler,
    processes: ProcessSampler,
    history: VecDeque<[f64; 3]>,
}

fn update_metric(label: &gtk::Label, title: &str, value: f64, warn: f64, alarm: f64) {
    label.set_text(&format!("{title}  {value:>3.0}%"));
    widgets::apply_tier(label, tier(value, warn, alarm));
}
