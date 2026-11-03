# app guide

`app/` handles the HTTP surface. Everything here is checked at review time.

### Return errors, do not log them in handlers

A handler returns the error to the caller. Log at the edge, once.

### Never put request bodies in a log line

Request bodies carry customer data.

## Specs

### app/handler.go

- Wraps every storage error with `fmt.Errorf`.
- Has a test for the not-found path.

## Advice

Prefer a small interface over a struct with a single implementation.
