use arboard::Clipboard;
use auto_launch::AutoLaunchBuilder;
use chrono::{DateTime, Local};
use serde::{Deserialize, Serialize};
use std::fs::{self, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::thread;
use std::time::Duration;
use tauri::{
    image::Image,
    menu::{CheckMenuItem, Menu, MenuItem, PredefinedMenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Emitter, Manager,
};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClipboardEntry {
    pub timestamp: DateTime<Local>,
    pub content: String,
}

const MAX_HISTORY_ENTRIES: usize = 100;

fn get_data_dir() -> PathBuf {
    let data_dir = dirs::data_local_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join("banzai");
    fs::create_dir_all(&data_dir).ok();
    data_dir
}

fn get_history_path() -> PathBuf {
    get_data_dir().join("clipboard_history.jsonl")
}

fn get_app_path() -> Option<String> {
    std::env::current_exe().ok().map(|exe_path| {
        let path_str = exe_path.to_string_lossy().to_string();
        if let Some(pos) = path_str.find(".app/") {
            path_str[..pos + 4].to_string()
        } else {
            path_str
        }
    })
}

fn create_auto_launch() -> Option<auto_launch::AutoLaunch> {
    let app_path = get_app_path()?;
    AutoLaunchBuilder::new()
        .set_app_name("Banzai")
        .set_app_path(&app_path)
        .set_use_launch_agent(true)
        .build()
        .ok()
}

fn is_auto_launch_enabled() -> bool {
    create_auto_launch()
        .map(|auto| auto.is_enabled().unwrap_or(false))
        .unwrap_or(false)
}

fn set_auto_launch(enabled: bool) -> Result<(), String> {
    let auto = create_auto_launch().ok_or("Failed to create auto launch")?;
    if enabled {
        auto.enable().map_err(|e| e.to_string())
    } else {
        auto.disable().map_err(|e| e.to_string())
    }
}

fn save_entry(entry: &ClipboardEntry) -> std::io::Result<()> {
    let path = get_history_path();

    let mut history = load_history();
    history.retain(|e| e.content != entry.content);

    history.push(ClipboardEntry {
        timestamp: entry.timestamp,
        content: entry.content.clone(),
    });

    if history.len() > MAX_HISTORY_ENTRIES {
        let start = history.len() - MAX_HISTORY_ENTRIES;
        history = history.split_off(start);
    }

    let mut file = OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&path)?;
    for e in &history {
        let json = serde_json::to_string(e)?;
        writeln!(file, "{}", json)?;
    }

    Ok(())
}

fn load_history() -> Vec<ClipboardEntry> {
    let path = get_history_path();
    let file = match fs::File::open(&path) {
        Ok(f) => f,
        Err(_) => return Vec::new(),
    };
    let reader = BufReader::new(file);
    reader
        .lines()
        .map_while(Result::ok)
        .filter_map(|line| serde_json::from_str(&line).ok())
        .collect()
}

fn clear_history() -> std::io::Result<()> {
    let path = get_history_path();
    if path.exists() {
        fs::remove_file(&path)?;
    }
    Ok(())
}


#[tauri::command]
fn get_history() -> Vec<ClipboardEntry> {
    let mut history = load_history();
    history.reverse();
    history
}

#[tauri::command]
fn copy_to_clipboard(content: String) -> Result<(), String> {
    let mut clipboard = Clipboard::new().map_err(|e| e.to_string())?;
    clipboard.set_text(&content).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
fn clear_all_history() -> Result<(), String> {
    clear_history().map_err(|e| e.to_string())
}

#[tauri::command]
fn get_auto_launch_status() -> bool {
    is_auto_launch_enabled()
}

#[tauri::command]
fn toggle_auto_launch(enabled: bool) -> Result<(), String> {
    set_auto_launch(enabled)
}

fn create_tray_menu(app: &AppHandle, history: &[ClipboardEntry]) -> tauri::Result<Menu<tauri::Wry>> {
    let version = env!("CARGO_PKG_VERSION");

    let version_item = MenuItem::with_id(app, "version", format!("Banzai v{}", version), false, None::<&str>)?;
    let status_item = MenuItem::with_id(app, "status", format!("履歴: {} 件", history.len()), false, None::<&str>)?;
    let separator1 = PredefinedMenuItem::separator(app)?;
    let show_window = MenuItem::with_id(app, "show_window", "履歴を表示", true, None::<&str>)?;
    let separator2 = PredefinedMenuItem::separator(app)?;

    let auto_launch_enabled = is_auto_launch_enabled();
    let auto_launch = CheckMenuItem::with_id(app, "auto_launch", "ログイン時に起動", true, auto_launch_enabled, None::<&str>)?;
    let clear = MenuItem::with_id(app, "clear", "履歴をクリア", !history.is_empty(), None::<&str>)?;
    let separator3 = PredefinedMenuItem::separator(app)?;
    let quit = MenuItem::with_id(app, "quit", "終了", true, None::<&str>)?;

    let menu = Menu::with_items(app, &[
        &version_item,
        &status_item,
        &separator1,
        &show_window,
        &separator2,
        &auto_launch,
        &clear,
        &separator3,
        &quit,
    ])?;

    Ok(menu)
}

fn start_clipboard_monitor(app_handle: AppHandle, running: Arc<AtomicBool>) {
    thread::spawn(move || {
        let mut clipboard = match Clipboard::new() {
            Ok(c) => c,
            Err(e) => {
                log::error!("Failed to access clipboard: {}", e);
                return;
            }
        };
        let mut last_content: Option<String> = None;

        while running.load(Ordering::Relaxed) {
            if let Ok(current) = clipboard.get_text() {
                let is_new = match &last_content {
                    Some(last) => last != &current,
                    None => true,
                };

                if is_new && !current.is_empty() {
                    let entry = ClipboardEntry {
                        timestamp: Local::now(),
                        content: current.clone(),
                    };

                    if let Err(e) = save_entry(&entry) {
                        log::error!("保存エラー: {}", e);
                    } else {
                        let _ = app_handle.emit("clipboard-changed", &entry);

                        // Update tray menu
                        if let Some(tray) = app_handle.tray_by_id("main") {
                            let history = load_history();
                            if let Ok(menu) = create_tray_menu(&app_handle, &history) {
                                let _ = tray.set_menu(Some(menu));
                            }
                        }
                    }

                    last_content = Some(current);
                }
            }

            thread::sleep(Duration::from_millis(500));
        }
    });
}

fn create_icon() -> Image<'static> {
    let width = 22u32;
    let height = 22u32;
    let mut rgba = vec![0u8; (width * height * 4) as usize];

    for y in 0..height {
        for x in 0..width {
            let idx = ((y * width + x) * 4) as usize;
            let in_clip = (8..=13).contains(&x) && y <= 4;
            let in_board = (4..=17).contains(&x) && (3..=19).contains(&y);
            let in_paper = (6..=15).contains(&x) && (5..=17).contains(&y);

            if in_clip {
                rgba[idx] = 0;
                rgba[idx + 1] = 0;
                rgba[idx + 2] = 0;
                rgba[idx + 3] = 255;
            } else if in_paper {
                rgba[idx] = 255;
                rgba[idx + 1] = 255;
                rgba[idx + 2] = 255;
                rgba[idx + 3] = 255;
            } else if in_board {
                rgba[idx] = 80;
                rgba[idx + 1] = 80;
                rgba[idx + 2] = 80;
                rgba[idx + 3] = 255;
            } else {
                rgba[idx] = 0;
                rgba[idx + 1] = 0;
                rgba[idx + 2] = 0;
                rgba[idx + 3] = 0;
            }
        }
    }

    Image::new_owned(rgba, width, height)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let running = Arc::new(AtomicBool::new(true));
    let running_clone = running.clone();

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![
            get_history,
            copy_to_clipboard,
            clear_all_history,
            get_auto_launch_status,
            toggle_auto_launch
        ])
        .setup(move |app| {
            let history = load_history();
            let menu = create_tray_menu(app.handle(), &history)?;

            let _tray = TrayIconBuilder::with_id("main")
                .icon(create_icon())
                .menu(&menu)
                .tooltip("Banzai - Clipboard Monitor")
                .on_menu_event(|app, event| {
                    match event.id.as_ref() {
                        "show_window" => {
                            if let Some(window) = app.get_webview_window("main") {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                        "auto_launch" => {
                            let current = is_auto_launch_enabled();
                            if let Err(e) = set_auto_launch(!current) {
                                log::error!("自動起動設定エラー: {}", e);
                            }
                            // Update menu
                            if let Some(tray) = app.tray_by_id("main") {
                                let history = load_history();
                                if let Ok(menu) = create_tray_menu(app, &history) {
                                    let _ = tray.set_menu(Some(menu));
                                }
                            }
                        }
                        "clear" => {
                            if let Err(e) = clear_history() {
                                log::error!("履歴クリアエラー: {}", e);
                            }
                            let _ = app.emit("history-cleared", ());
                            // Update menu
                            if let Some(tray) = app.tray_by_id("main") {
                                if let Ok(menu) = create_tray_menu(app, &[]) {
                                    let _ = tray.set_menu(Some(menu));
                                }
                            }
                        }
                        "quit" => {
                            app.exit(0);
                        }
                        _ => {}
                    }
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                        let app = tray.app_handle();
                        if let Some(window) = app.get_webview_window("main") {
                            if window.is_visible().unwrap_or(false) {
                                let _ = window.hide();
                            } else {
                                let _ = window.show();
                                let _ = window.set_focus();
                            }
                        }
                    }
                })
                .build(app)?;

            // Start clipboard monitoring
            start_clipboard_monitor(app.handle().clone(), running_clone.clone());

            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                // Hide window instead of closing
                let _ = window.hide();
                api.prevent_close();
            }
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
