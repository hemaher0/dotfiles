use std::{
    env,
    error::Error,
    io::{self, Stdout},
    path::{Path, PathBuf},
    process::Command,
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

    fn action_label(&self) -> String {
        if self.action_kind == "none" || self.action_target.is_empty() {
            "-".to_owned()
        } else {
            format!("--{} {}", self.action_kind, self.action_target)
        }
    }

    fn has_action(&self) -> bool {
        self.action_kind != "none" && !self.action_target.is_empty()
    }
}

struct App {
    repo_root: PathBuf,
    components: Vec<Component>,
    selected: usize,
    log: Vec<String>,
}

impl App {
    fn new(repo_root: PathBuf) -> Self {
        Self {
            repo_root,
            components: Vec::new(),
            selected: 0,
            log: Vec::new(),
        }
    }

    fn dot_path(&self) -> PathBuf {
        self.repo_root.join("bin").join("dot")
    }

    fn refresh(&mut self) {
        match load_components(&self.repo_root) {
            Ok(components) => {
                self.components = components;
                if self.selected >= self.components.len() {
                    self.selected = self.components.len().saturating_sub(1);
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

    fn selected_component(&self) -> Option<&Component> {
        self.components.get(self.selected)
    }

    fn run_selected_action(&mut self) {
        let Some(component) = self.selected_component().cloned() else {
            self.push_log("no component selected");
            return;
        };

        if !component.has_action() {
            self.push_log(format!("no action for {}", component.id));
            return;
        }

        let action_flag = format!("--{}", component.action_kind);
        self.push_log(format!(
            "running: bin/dot update {action_flag} {}",
            component.action_target
        ));

        match Command::new(self.dot_path())
            .arg("update")
            .arg(action_flag)
            .arg(&component.action_target)
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
    let repo_root = env::args()
        .nth(1)
        .map(PathBuf::from)
        .unwrap_or(env::current_dir()?);
    let mut app = App::new(repo_root);
    app.refresh();

    let mut terminal = TerminalGuard::new()?;

    loop {
        terminal.terminal.draw(|frame| draw(frame, &app))?;

        if event::poll(Duration::from_millis(200))? {
            if let Event::Key(key) = event::read()? {
                if key.kind != KeyEventKind::Press {
                    continue;
                }

                match key.code {
                    KeyCode::Char('q') | KeyCode::Esc => break,
                    KeyCode::Char('r') => app.refresh(),
                    KeyCode::Enter => app.run_selected_action(),
                    KeyCode::Up | KeyCode::Char('k') => app.move_up(),
                    KeyCode::Down | KeyCode::Char('j') => app.move_down(),
                    _ => {}
                }
            }
        }
    }

    Ok(())
}

fn load_components(repo_root: &Path) -> AppResult<Vec<Component>> {
    let output = Command::new(repo_root.join("bin").join("dot"))
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

fn draw(frame: &mut ratatui::Frame<'_>, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(8),
            Constraint::Length(3),
            Constraint::Length(8),
        ])
        .split(frame.area());

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
        Span::raw("  selected: "),
        Span::styled(selected, Style::default().fg(Color::Yellow)),
    ]))
    .block(Block::default().borders(Borders::ALL).title("Ratatui"));
    frame.render_widget(header, chunks[0]);

    let rows = app.components.iter().enumerate().map(|(index, component)| {
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
            Cell::from(component.action_label()),
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

    let help = Paragraph::new("Up/Down or j/k: move  Enter: run action  r: refresh  q/Esc: quit")
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
        "unknown" => Style::default().fg(Color::Yellow),
        _ => Style::default(),
    }
}
