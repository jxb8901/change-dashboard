# Architecture

Dashboard
 -> Scheduler
 -> Panel Manager
 -> Command Executor
 -> Renderer
 -> Terminal

Each panel = title + command + position + size + refresh interval.
Dashboard never contains business logic.
