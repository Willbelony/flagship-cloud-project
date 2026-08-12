from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel, Field

app = FastAPI(
    title="Cloud Project API",
    description="Flagship portfolio API — task tracker backend, deployed on EC2/Docker/Terraform.",
    version="0.1.0",
)

# In-memory store for now — Phase 3 swaps this for RDS Postgres.
# Kept as a module-level dict so the swap later is a clean drop-in
# (same function signatures, different persistence underneath).
_tasks: dict[UUID, "Task"] = {}


class TaskCreate(BaseModel):
    title: str = Field(min_length=1, max_length=200)
    done: bool = False


class Task(BaseModel):
    id: UUID
    title: str
    done: bool
    created_at: datetime


@app.get("/health")
def health() -> dict:
    """Liveness/readiness check — this is what the ALB target group
    and CloudWatch will poll in later phases."""
    return {"status": "ok", "time": datetime.now(timezone.utc).isoformat()}


@app.get("/tasks", response_model=list[Task])
def list_tasks() -> list[Task]:
    return list(_tasks.values())


@app.post("/tasks", response_model=Task, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate) -> Task:
    task = Task(
        id=uuid4(),
        title=payload.title,
        done=payload.done,
        created_at=datetime.now(timezone.utc),
    )
    _tasks[task.id] = task
    return task


@app.get("/tasks/{task_id}", response_model=Task)
def get_task(task_id: UUID) -> Task:
    task = _tasks.get(task_id)
    if task is None:
        raise HTTPException(status_code=404, detail="Task not found")
    return task


@app.patch("/tasks/{task_id}", response_model=Task)
def update_task(task_id: UUID, payload: TaskCreate) -> Task:
    if task_id not in _tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    task = _tasks[task_id]
    updated = task.model_copy(update={"title": payload.title, "done": payload.done})
    _tasks[task_id] = updated
    return updated


@app.delete("/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: UUID) -> None:
    if task_id not in _tasks:
        raise HTTPException(status_code=404, detail="Task not found")
    del _tasks[task_id]
