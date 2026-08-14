import os
from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, status
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import Column, DateTime, String, Boolean, create_engine
from sqlalchemy.dialects.postgresql import UUID as PG_UUID
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

DATABASE_URL = os.environ["DATABASE_URL"]  # fails fast/loudly if not set — no silent fallback

engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class TaskRow(Base):
    __tablename__ = "tasks"

    id = Column(PG_UUID(as_uuid=True), primary_key=True, default=uuid4)
    title = Column(String(200), nullable=False)
    done = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc))


_FRONTEND_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Task Tracker — Cloud Project</title>
<style>
  :root {
    --bg: #0f1115;
    --card: #171a21;
    --border: #2a2f3a;
    --text: #e8eaed;
    --muted: #8b93a3;
    --accent: #5b8def;
    --accent-hover: #4a7bd9;
    --done: #4caf6d;
    --danger: #e5566d;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0;
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: var(--bg);
    color: var(--text);
    display: flex;
    justify-content: center;
    padding: 48px 16px;
  }
  .card {
    width: 100%;
    max-width: 520px;
  }
  h1 {
    font-size: 22px;
    margin: 0 0 4px 0;
  }
  .subtitle {
    color: var(--muted);
    font-size: 13px;
    margin: 0 0 24px 0;
  }
  .subtitle a { color: var(--accent); }
  form {
    display: flex;
    gap: 8px;
    margin-bottom: 20px;
  }
  input[type=text] {
    flex: 1;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 10px 12px;
    color: var(--text);
    font-size: 14px;
  }
  input[type=text]:focus { outline: 2px solid var(--accent); }
  button {
    background: var(--accent);
    color: white;
    border: none;
    border-radius: 8px;
    padding: 10px 16px;
    font-size: 14px;
    cursor: pointer;
  }
  button:hover { background: var(--accent-hover); }
  .task {
    display: flex;
    align-items: center;
    gap: 10px;
    background: var(--card);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 12px 14px;
    margin-bottom: 8px;
  }
  .task.done .title { text-decoration: line-through; color: var(--muted); }
  .task .title { flex: 1; font-size: 14px; }
  .task input[type=checkbox] { width: 18px; height: 18px; accent-color: var(--done); cursor: pointer; }
  .task .delete {
    background: transparent;
    color: var(--danger);
    padding: 4px 8px;
    font-size: 16px;
  }
  .task .delete:hover { background: rgba(229,86,109,0.15); }
  .empty { color: var(--muted); font-size: 13px; text-align: center; padding: 24px 0; }
</style>
</head>
<body>
<div class="card">
  <h1>Task Tracker</h1>
  <p class="subtitle">Backend: FastAPI + RDS Postgres, running on EC2 behind an ALB &middot; <a href="/docs">API docs</a></p>

  <form id="add-form">
    <input type="text" id="title-input" placeholder="Add a task..." required maxlength="200">
    <button type="submit">Add</button>
  </form>

  <div id="task-list"></div>
</div>

<script>
async function loadTasks() {
  const res = await fetch('/tasks');
  const tasks = await res.json();
  const list = document.getElementById('task-list');
  list.innerHTML = '';
  if (tasks.length === 0) {
    list.innerHTML = '<div class="empty">No tasks yet — add one above.</div>';
    return;
  }
  for (const task of tasks) {
    const row = document.createElement('div');
    row.className = 'task' + (task.done ? ' done' : '');
    row.innerHTML = `
      <input type="checkbox" ${task.done ? 'checked' : ''} data-id="${task.id}" data-title="${task.title.replace(/"/g, '&quot;')}">
      <span class="title">${task.title}</span>
      <button class="delete" data-id="${task.id}">&times;</button>
    `;
    list.appendChild(row);
  }
}

document.getElementById('add-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const input = document.getElementById('title-input');
  const title = input.value.trim();
  if (!title) return;
  await fetch('/tasks', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title })
  });
  input.value = '';
  loadTasks();
});

document.getElementById('task-list').addEventListener('change', async (e) => {
  if (e.target.type !== 'checkbox') return;
  const id = e.target.dataset.id;
  const title = e.target.dataset.title;
  await fetch(`/tasks/${id}`, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ title, done: e.target.checked })
  });
  loadTasks();
});

document.getElementById('task-list').addEventListener('click', async (e) => {
  if (!e.target.classList.contains('delete')) return;
  const id = e.target.dataset.id;
  await fetch(`/tasks/${id}`, { method: 'DELETE' });
  loadTasks();
});

loadTasks();
</script>
</body>
</html>
"""


app = FastAPI(
    title="Cloud Project API",
    description="Flagship portfolio API — task tracker backend, backed by RDS Postgres.",
    version="0.2.0",
)


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


@app.get("/", response_class=HTMLResponse)
def frontend() -> str:
    return _FRONTEND_HTML


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    done: bool = False


class Task(BaseModel):
    id: UUID
    title: str
    done: bool
    created_at: datetime

    class Config:
        from_attributes = True


@app.get("/health")
def health() -> dict:
    """Liveness/readiness check — also confirms DB connectivity,
    since a broken DB connection should fail the health check."""
    with SessionLocal() as db:
        db.execute(TaskRow.__table__.select().limit(1))
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/tasks", response_model=list[Task])
def list_tasks() -> list[Task]:
    with SessionLocal() as db:
        rows = db.query(TaskRow).order_by(TaskRow.created_at.desc()).all()
        return [Task.model_validate(r) for r in rows]


@app.post("/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate) -> Task:
    with SessionLocal() as db:
        row = TaskRow(id=uuid4(), title=payload.title, done=payload.done)
        db.add(row)
        db.commit()
        db.refresh(row)
        return Task.model_validate(row)


@app.get("/tasks/{task_id}", response_model=Task)
def get_task(task_id: UUID) -> Task:
    with SessionLocal() as db:
        row = db.get(TaskRow, task_id)
        if row is None:
            raise HTTPException(status_code=404, detail="Task not found")
        return Task.model_validate(row)


@app.patch("/tasks/{task_id}", response_model=Task)
def update_task(task_id: UUID, payload: TaskCreate) -> Task:
    with SessionLocal() as db:
        row = db.get(TaskRow, task_id)
        if row is None:
            raise HTTPException(status_code=404, detail="Task not found")
        row.title = payload.title
        row.done = payload.done
        db.commit()
        db.refresh(row)
        return Task.model_validate(row)


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: UUID) -> None:
    with SessionLocal() as db:
        row = db.get(TaskRow, task_id)
        if row is None:
            raise HTTPException(status_code=404, detail="Task not found")
        db.delete(row)
        db.commit()
