use std::{
    env,
    error::Error,
    io::{self, Stdout},
    path::{Path, PathBuf},
    process::{Command, Stdio},
    time::Duration,
};

use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Constraint, Direction, Layout},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Cell, Paragraph, Row, Table, Wrap},
    Terminal,
};

type AppResult<T> = Result<T, Box<dyn Error>>;

#[derive(Clone, Debug)]
struct Component {
    status: String,
    category: String,
    group: String,
    scope: String,
    id: String,
    name: String,
    method: String,
    current: String,
    policy: String,
    relation: String,
    action_kind: String,
    action_target: String,
}

impl Component {
    fn from_raw_line(line: &str) -> Option<Self> {
        let mut fields = line.split('|');
        Some(Self {
            status: fields.next()?.to_owned(),
            category: fields.next()?.to_owned(),
            group: fields.next()?.to_owned(),
            scope: fields.next()?.to_owned(),
            id: fields.next()?.to_owned(),
            name: fields.next()?.to_owned(),
            method: fields.next()?.to_owned(),
            current: fields.next().unwrap_or_default().to_owned(),
            policy: fields.next().unwrap_or_default().to_owned(),
            relation: fields.next().unwrap_or_default().to_owned(),
            action_kind: fields.next().unwrap_or_default().to_owned(),
            action_target: fields.next().unwrap_or_default().to_owned(),
        })
    }

    fn action_label(&self, command_display_name: &str) -> String {
        if self.action_kind == "none" || self.action_target.is_empty() {
            "-".to_owned()
        } else {
            format!(
                "{} update --{} {}",
                command_display_name, self.action_kind, self.action_target
            )
        }
    }
}

#[derive(Clone, Debug)]
struct DotCommand {
    program: PathBuf,
    prefix_args: Vec<String>,
    display_name: String,
}

impl DotCommand {
    fn resolve(repo_root: &Path) -> Self {
        let shell_dot = repo_root.join("bin").join("dot");

        if cfg!(windows) {
            let powershell_dot = repo_root.join("bin").join("dot.ps1");
            if powershell_dot.is_file() {
                if let Some(shell) = find_powershell() {
                    return Self {
                        program: PathBuf::from(shell),
                        prefix_args: vec![
                            "-NoLogo".to_owned(),
                            "-NoProfile".to_owned(),
                            "-ExecutionPolicy".to_owned(),
                            "Bypass".to_owned(),
                            "-Command".to_owned(),
                            powershell_script_command(&powershell_dot),
                        ],
                        display_name: "bin/dot.ps1".to_owned(),
                    };
                }
            }

            if command_available("sh") {
                return Self {
                    program: PathBuf::from("sh"),
                    prefix_args: vec![shell_dot.to_string_lossy().into_owned()],
                    display_name: "bin/dot".to_owned(),
                };
            }
        }

        Self {
            program: shell_dot,
            prefix_args: Vec::new(),
            display_name: "bin/dot".to_owned(),
        }
    }

    fn command(&self) -> Command {
        let mut command = Command::new(&self.program);
        command.args(&self.prefix_args);
        command
    }

    fn render(&self, command_name: &str, args: &[&str]) -> String {
        let mut rendered = format!("{} {}", self.display_name, command_name);
        if !args.is_empty() {
            rendered.push(' ');
            rendered.push_str(&args.join(" "));
        }
        rendered
    }
}

struct App {
    repo_root: PathBuf,
    dot_command: DotCommand,
    components: Vec<Component>,
    selected: usize,
    scroll_offset: usize,
    log: Vec<String>,
}

impl App {
    fn new(repo_root: PathBuf) -> Self {
        let dot_command = DotCommand::resolve(&repo_root);
        Self {
            repo_root,
            dot_command,
            components: Vec::new(),
            selected: 0,
            scroll_offset: 0,
            log: Vec::new(),
        }
    }

    fn refresh(&mut self) {
        match load_components(&self.repo_root) {
            Ok(components) => {
                self.components = components;
                if self.selected >= self.components.len() {
                    self.selected = self.components.len().saturating_sub(1);
                }
                if self.scroll_offset >= self.components.len() {
                    self.scroll_offset = self.components.len().saturating_sub(1);
                }
                self.push_log("status refreshed");
            }
            Err(error) => self.push_log(format!("refresh failed: {error}")),
        }
    }

    fn move_up(&mut self) {
        self.selected = self.selected.saturating_sub(1);
    }

    fn move_down(&mut self) {
        if self.selected + 1 < self.components.len() {
            self.selected += 1;
        }
    }

    fn page_up(&mut self, page_size: usize) {
        self.selected = self.selected.saturating_sub(page_size.max(1));
    }

    fn page_down(&mut self, page_size: usize) {
        if self.components.is_empty() {
            return;
        }

        self.selected = (self.selected + page_size.max(1)).min(self.components.len() - 1);
    }

    fn ensure_selected_visible(&mut self, visible_rows: usize) {
        let visible_rows = visible_rows.max(1);
        if self.selected < self.scroll_offset {
            self.scroll_offset = self.selected;
        } else if self.selected >= self.scroll_offset + visible_rows {
            self.scroll_offset = self.selected + 1 - visible_rows;
        }
    }

    fn selected_component(&self) -> Option<&Component> {
        self.components.get(self.selected)
    }

    fn run_selected_action(&mut self) {
        self.run_action_for_selected(None);
    }

    fn run_action_for_selected(&mut self, requested_action: Option<&str>) {
        let Some(component) = self.selected_component().cloned() else {
            self.push_log("no component selected");
            return;
        };

        let action_kind = requested_action.unwrap_or(&component.action_kind);
        let action_target = if requested_action.is_some() {
            &component.id
        } else {
            &component.action_target
        };

        if action_kind == "none" || action_target.is_empty() {
            self.push_log(format!("no action for {}", component.id));
            return;
        }

        let action_flag = format!("--{action_kind}");
        self.run_dot_command("update", &[&action_flag, action_target]);
    }

    fn run_dot_command(&mut self, command_name: &str, args: &[&str]) {
        self.push_log(format!(
            "running: {}",
            self.dot_command.render(command_name, args)
        ));

        match self
            .dot_command
            .command()
            .arg(command_name)
            .args(args)
            .current_dir(&self.repo_root)
            .output()
        {
            Ok(output) => {
                for line in String::from_utf8_lossy(&output.stdout).lines() {
                    self.push_log(line.to_owned());
                }
                for line in String::from_utf8_lossy(&output.stderr).lines() {
                    self.push_log(line.to_owned());
                }
                self.push_log(format!("exit: {}", output.status));
                self.refresh();
            }
            Err(error) => self.push_log(format!("action failed: {error}")),
        }
    }

    fn push_log(&mut self, line: impl Into<String>) {
        self.log.push(line.into());
        if self.log.len() > 200 {
            let remove_count = self.log.len() - 200;
            self.log.drain(0..remove_count);
        }
    }
}

struct TerminalGuard {
    terminal: Terminal<CrosstermBackend<Stdout>>,
}

impl TerminalGuard {
    fn new() -> io::Result<Self> {
        enable_raw_mode()?;
        let mut stdout = io::stdout();
        execute!(stdout, EnterAlternateScreen)?;
        let backend = CrosstermBackend::new(stdout);
        let terminal = Terminal::new(backend)?;
        Ok(Self { terminal })
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(self.terminal.backend_mut(), LeaveAlternateScreen);
        let _ = self.terminal.show_cursor();
    }
}

fn main() -> AppResult<()> {
    let mut dump = false;
    let mut repo_root = None;

    for arg in env::args().skip(1) {
        if arg == "--dump" {
            dump = true;
        } else {
            repo_root = Some(PathBuf::from(arg));
        }
    }

    let repo_root = repo_root.unwrap_or(env::current_dir()?);

    if dump {
        for component in load_components(&repo_root)? {
            println!(
                "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
                component.status,
                component.category,
                component.group,
                component.scope,
                component.id,
                component.name,
                component.method,
                component.current,
                component.policy,
                component.relation,
                component.action_kind,
                component.action_target
            );
        }
        return Ok(());
    }

    let mut app = App::new(repo_root);
    app.refresh();

    let mut terminal = TerminalGuard::new()?;

    loop {
        terminal.terminal.draw(|frame| draw(frame, &mut app))?;

        if event::poll(Duration::from_millis(200))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }

                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => break,
                    KeyCode::Char('r') => app.refresh(),
                    KeyCode::Enter => app.run_selected_action(),
                    KeyCode::Char(' ') | KeyCode::Char('i') => {
                        app.run_action_for_selected(Some("install"))
                    }
                    KeyCode::Char('s') => app.run_action_for_selected(Some("sync")),
                    KeyCode::Char('u') => app.run_action_for_selected(Some("update")),
                    KeyCode::Char('b') => app.run_action_for_selected(Some("build")),
                    KeyCode::Up | KeyCode::Char('k') => app.move_up(),
                    KeyCode::Down | KeyCode::Char('j') => app.move_down(),
                    KeyCode::PageUp => {
                        app.page_up(visible_table_rows(terminal.terminal.size()?.height))
                    }
                    KeyCode::PageDown => {
                        app.page_down(visible_table_rows(terminal.terminal.size()?.height))
                    }
                    _ => {}
                }
            }
        }
    }

    Ok(())
}

fn load_components(repo_root: &Path) -> AppResult<Vec<Component>> {
    let dot_command = DotCommand::resolve(repo_root);
    let output = dot_command
        .command()
        .arg("update")
        .arg("--raw")
        .current_dir(repo_root)
        .output()?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(format!("bin/dot update --raw failed: {stdout}{stderr}").into());
    }

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .filter_map(Component::from_raw_line)
        .collect())
}

fn find_powershell() -> Option<&'static str> {
    ["pwsh", "powershell"]
        .into_iter()
        .find(|shell| powershell_available(shell))
}

fn powershell_script_command(script_path: &Path) -> String {
    format!(
        "& '{}'",
        script_path.to_string_lossy().replace('\'', "''")
    )
}

fn powershell_available(shell: &str) -> bool {
    Command::new(shell)
        .arg("-NoLogo")
        .arg("-NoProfile")
        .arg("-Command")
        .arg("$PSVersionTable.PSVersion.Major | Out-Null")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok()
}

fn command_available(command_name: &str) -> bool {
    Command::new(command_name)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok()
}

fn visible_table_rows(total_height: u16) -> usize {
    usize::from(total_height.saturating_sub(19).max(1))
}

fn table_visible_rows(table_height: u16) -> usize {
    usize::from(table_height.saturating_sub(3).max(1))
}

fn draw(frame: &mut ratatui::Frame<'_>, app: &mut App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(8),
            Constraint::Length(5),
            Constraint::Length(8),
        ])
        .split(frame.area());
    let visible_rows = table_visible_rows(chunks[1].height);
    app.ensure_selected_visible(visible_rows);

    let selected = app
        .selected_component()
        .map(|component| component.id.as_str())
        .unwrap_or("-");
    let header = Paragraph::new(Line::from(vec![
        Span::styled(
            "dotfiles update",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw("  "),
        Span::raw(format!("{} components", app.components.len())),
        Span::raw(format!(
            "  rows: {}-{}",
            app.scroll_offset.saturating_add(1),
            (app.scroll_offset + visible_rows).min(app.components.len())
        )),
        Span::raw("  selected: "),
        Span::styled(selected, Style::default().fg(Color::Yellow)),
    ]))
    .block(Block::default().borders(Borders::ALL).title("Ratatui"));
    frame.render_widget(header, chunks[0]);

    let rows = app
        .components
        .iter()
        .enumerate()
        .skip(app.scroll_offset)
        .take(visible_rows)
        .map(|(index, component)| {
            let command_display_name = app.dot_command.display_name.as_str();
            let mut style = status_style(&component.status);
            if index == app.selected {
                style = style.bg(Color::DarkGray).add_modifier(Modifier::BOLD);
            }

            Row::new(vec![
                Cell::from(component.status.clone()),
                Cell::from(component.category.clone()),
                Cell::from(component.group.clone()),
                Cell::from(component.scope.clone()),
                Cell::from(component.id.clone()),
                Cell::from(component.name.clone()),
                Cell::from(component.method.clone()),
                Cell::from(empty_dash(&component.current)),
                Cell::from(empty_dash(&component.policy)),
                Cell::from(empty_dash(&component.relation)),
                Cell::from(component.action_label(command_display_name)),
            ])
            .style(style)
        });

    let table = Table::new(
        rows,
        [
            Constraint::Length(8),
            Constraint::Length(11),
            Constraint::Length(10),
            Constraint::Length(7),
            Constraint::Length(26),
            Constraint::Length(30),
            Constraint::Length(12),
            Constraint::Length(16),
            Constraint::Length(28),
            Constraint::Length(20),
            Constraint::Min(18),
        ],
    )
    .header(
        Row::new(vec![
            "STATUS",
            "CATEGORY",
            "GROUP",
            "SCOPE",
            "ID",
            "COMPONENT",
            "METHOD",
            "CURRENT",
            "POLICY",
            "RELATION",
            "ACTION",
        ])
        .style(
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
    )
    .block(Block::default().borders(Borders::ALL).title("Components"));
    frame.render_widget(table, chunks[1]);

    let selected_action = app
        .selected_component()
        .map(|component| component.action_label(&app.dot_command.display_name))
        .unwrap_or_else(|| "-".to_owned());
    let help = Paragraph::new(format!(
        "j/k or Up/Down: move  PgUp/PgDn: page  Enter: row action  Space/i: install\ns: sync  u: update  b: build  r: refresh  q/Esc: quit\nselected action: {selected_action}"
    ))
    .block(Block::default().borders(Borders::ALL).title("Keys"));
    frame.render_widget(help, chunks[2]);

    let log_text = app
        .log
        .iter()
        .rev()
        .take(6)
        .rev()
        .cloned()
        .collect::<Vec<_>>()
        .join("\n");
    let log = Paragraph::new(log_text)
        .wrap(Wrap { trim: false })
        .block(Block::default().borders(Borders::ALL).title("Log"));
    frame.render_widget(log, chunks[3]);
}

fn empty_dash(value: &str) -> String {
    if value.is_empty() {
        "-".to_owned()
    } else {
        value.to_owned()
    }
}

fn status_style(status: &str) -> Style {
    match status {
        "ok" => Style::default().fg(Color::Green),
        "missing" => Style::default().fg(Color::Red),
        "unknown" | "outdated" => Style::default().fg(Color::Yellow),
        _ => Style::default(),
    }
}
