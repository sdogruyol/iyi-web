"""FastAPI's side of bench/compare: the three endpoints, typed as FastAPI
code is written (`id: int`, `fields: str = ""`) and `async def`, since none
of them blocks. bench/compare/run.iyi runs it under uvicorn with one worker
process per core, access log off, and httptools when it is installed:

    python -m uvicorn app:app --port 3000 --workers 12 --no-access-log --http httptools
"""
from fastapi import FastAPI
from fastapi.responses import PlainTextResponse

app = FastAPI()


@app.get("/plaintext", response_class=PlainTextResponse)
async def plaintext() -> str:
    return "Hello, World!"


@app.get("/json")
async def json() -> dict:
    return {"message": "Hello, World!"}


@app.get("/users/{id}")
async def user(id: int, fields: str = "") -> dict:
    return {"id": id, "name": f"user-{id}", "fields": fields}
