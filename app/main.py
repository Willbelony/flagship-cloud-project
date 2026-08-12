import os
from datetime import datetime, timezone
from uuid import UUID, uuid4

from fastapi import FastAPI, HTTPException, status
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


app = FastAPI(
    title="Cloud Project API",
    description="Flagship portfolio API — task tracker backend, backed by RDS Postgres.",
    version="0.2.0",
)


@app.on_event("startup")
def on_startup() -> None:
    Base.metadata.create_all(bind=engine)


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
