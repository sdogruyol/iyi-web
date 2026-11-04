"""FastAPI's side of bench/compare: the endpoints, typed as FastAPI code is
written (`id: int`, `fields: str = ""`) and `async def`, since none of them
blocks. bench/compare/run.iyi runs it under uvicorn with one worker process
per core, access log off, and httptools when it is installed:

    python -m uvicorn app:app --port 3000 --workers 12 --no-access-log --http httptools

`/db` is there when DATABASE_URL is: an asyncpg pool per worker process,
DB_POOL_SIZE connections each (default 4), opened when the worker starts.
"""
import os
import random
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

DATABASE_URL = os.environ.get("DATABASE_URL")
pool = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global pool
    if DATABASE_URL:
        import asyncpg

        size = int(os.environ.get("DB_POOL_SIZE") or 4)
        pool = await asyncpg.create_pool(DATABASE_URL, min_size=size, max_size=size)
    yield
    if pool:
        await pool.close()


app = FastAPI(lifespan=lifespan)


@app.get("/plaintext", response_class=PlainTextResponse)
async def plaintext() -> str:
    return "Hello, World!"


@app.get("/json")
async def json() -> dict:
    return {"message": "Hello, World!"}


@app.get("/users/{id}")
async def user(id: int, fields: str = "") -> dict:
    return {"id": id, "name": f"user-{id}", "fields": fields}


if DATABASE_URL:

    @app.get("/db")
    async def single_query() -> dict:
        async with pool.acquire() as connection:
            row = await connection.fetchrow("SELECT id, randomnumber FROM world WHERE id = $1", random.randint(1, 10000))
        return {"id": row["id"], "randomNumber": row["randomnumber"]}
