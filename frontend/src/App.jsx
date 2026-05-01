import { useState, useEffect } from 'react'

// API base — at runtime, NGINX proxies /api requests to the backend service.
// In dev, points at localhost:8080.
const API_BASE = import.meta.env.DEV ? 'http://localhost:8080' : ''

const STATUS = ['TODO', 'IN_PROGRESS', 'IN_REVIEW', 'DONE', 'ARCHIVED']
const PRIORITY = ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']

const statusColor = {
  TODO:        'bg-slate-700 text-slate-200',
  IN_PROGRESS: 'bg-blue-700 text-blue-100',
  IN_REVIEW:   'bg-amber-700 text-amber-100',
  DONE:        'bg-emerald-700 text-emerald-100',
  ARCHIVED:    'bg-zinc-700 text-zinc-300',
}

const priorityColor = {
  LOW:      'text-slate-400',
  MEDIUM:   'text-blue-400',
  HIGH:     'text-amber-400',
  CRITICAL: 'text-red-400',
}

export default function App() {
  const [tasks, setTasks] = useState([])
  const [health, setHealth] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)
  const [form, setForm] = useState({
    title: '', description: '', status: 'TODO', priority: 'MEDIUM', assignedTo: ''
  })

  async function loadTasks() {
    try {
      const res = await fetch(`${API_BASE}/api/tasks`)
      if (!res.ok) throw new Error(`API returned ${res.status}`)
      setTasks(await res.json())
      setError(null)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  async function loadHealth() {
    try {
      const res = await fetch(`${API_BASE}/actuator/health`)
      setHealth(await res.json())
    } catch { setHealth({ status: 'DOWN' }) }
  }

  useEffect(() => {
    loadTasks()
    loadHealth()
    const t = setInterval(loadHealth, 10000)
    return () => clearInterval(t)
  }, [])

  async function createTask(e) {
    e.preventDefault()
    if (!form.title.trim()) return
    await fetch(`${API_BASE}/api/tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(form),
    })
    setForm({ title: '', description: '', status: 'TODO', priority: 'MEDIUM', assignedTo: '' })
    loadTasks()
  }

  async function updateStatus(task, newStatus) {
    await fetch(`${API_BASE}/api/tasks/${task.id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ...task, status: newStatus }),
    })
    loadTasks()
  }

  async function deleteTask(id) {
    if (!confirm('Delete this task?')) return
    await fetch(`${API_BASE}/api/tasks/${id}`, { method: 'DELETE' })
    loadTasks()
  }

  const grouped = STATUS.reduce((acc, s) => {
    acc[s] = tasks.filter(t => t.status === s)
    return acc
  }, {})

  return (
    <div className="min-h-screen text-slate-100 p-6">
      {/* Header */}
      <header className="max-w-7xl mx-auto mb-8">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-3xl font-bold tracking-tight">
              <span className="text-orange-500">Deploy</span>Forge
            </h1>
            <p className="text-sm text-slate-400 mt-1">
              Cloud-native task management on self-managed Kubernetes
            </p>
          </div>
          <div className="flex items-center gap-3 text-sm">
            <div className={`flex items-center gap-2 px-3 py-1.5 rounded-md
              ${health?.status === 'UP' ? 'bg-emerald-900/40 text-emerald-300' : 'bg-red-900/40 text-red-300'}`}>
              <span className={`w-2 h-2 rounded-full
                ${health?.status === 'UP' ? 'bg-emerald-400 animate-pulse' : 'bg-red-400'}`} />
              {health?.status || 'CHECKING'}
            </div>
            <span className="text-slate-500">{tasks.length} tasks</span>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto grid grid-cols-1 lg:grid-cols-4 gap-6">
        {/* Create form */}
        <section className="lg:col-span-1 bg-slate-900 border border-slate-800 rounded-lg p-5">
          <h2 className="font-semibold mb-4 text-slate-200">Create Task</h2>
          <form onSubmit={createTask} className="space-y-3">
            <input
              className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-sm focus:outline-none focus:border-orange-500"
              placeholder="Title"
              value={form.title}
              onChange={e => setForm({ ...form, title: e.target.value })}
              required
            />
            <textarea
              className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-sm focus:outline-none focus:border-orange-500"
              placeholder="Description (optional)"
              rows="3"
              value={form.description}
              onChange={e => setForm({ ...form, description: e.target.value })}
            />
            <select
              className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-sm"
              value={form.priority}
              onChange={e => setForm({ ...form, priority: e.target.value })}
            >
              {PRIORITY.map(p => <option key={p}>{p}</option>)}
            </select>
            <input
              className="w-full bg-slate-950 border border-slate-700 rounded px-3 py-2 text-sm focus:outline-none focus:border-orange-500"
              placeholder="Assigned to"
              value={form.assignedTo}
              onChange={e => setForm({ ...form, assignedTo: e.target.value })}
            />
            <button
              type="submit"
              className="w-full bg-orange-600 hover:bg-orange-500 text-white font-medium py-2 rounded transition"
            >
              Add Task
            </button>
          </form>

          <div className="mt-6 pt-4 border-t border-slate-800 text-xs text-slate-500 space-y-1">
            <div>API: <code className="text-slate-400">/api/tasks</code></div>
            <div>Health: <code className="text-slate-400">/actuator/health</code></div>
            <div>Metrics: <code className="text-slate-400">/actuator/prometheus</code></div>
          </div>
        </section>

        {/* Kanban board */}
        <section className="lg:col-span-3 grid grid-cols-1 md:grid-cols-2 xl:grid-cols-5 gap-4">
          {STATUS.map(s => (
            <div key={s} className="bg-slate-900 border border-slate-800 rounded-lg p-3">
              <div className="flex items-center justify-between mb-3">
                <span className={`text-xs font-semibold px-2 py-1 rounded ${statusColor[s]}`}>
                  {s.replace('_', ' ')}
                </span>
                <span className="text-xs text-slate-500">{grouped[s].length}</span>
              </div>
              <div className="space-y-2 min-h-[100px]">
                {grouped[s].map(task => (
                  <div key={task.id} className="bg-slate-950 border border-slate-800 rounded p-3 text-sm">
                    <div className="flex items-start justify-between gap-2">
                      <h3 className="font-medium text-slate-200 break-words">{task.title}</h3>
                      <button
                        onClick={() => deleteTask(task.id)}
                        className="text-slate-600 hover:text-red-400 text-xs"
                        title="Delete"
                      >
                        ✕
                      </button>
                    </div>
                    {task.description && (
                      <p className="text-xs text-slate-500 mt-1 line-clamp-2">{task.description}</p>
                    )}
                    <div className="flex items-center justify-between mt-3 text-xs">
                      <span className={`font-medium ${priorityColor[task.priority]}`}>
                        ● {task.priority}
                      </span>
                      {task.assignedTo && (
                        <span className="text-slate-500">@{task.assignedTo}</span>
                      )}
                    </div>
                    <select
                      value={task.status}
                      onChange={e => updateStatus(task, e.target.value)}
                      className="mt-2 w-full bg-slate-900 border border-slate-800 rounded px-2 py-1 text-xs"
                    >
                      {STATUS.map(opt => <option key={opt}>{opt}</option>)}
                    </select>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </section>
      </main>

      {/* Footer */}
      <footer className="max-w-7xl mx-auto mt-8 pt-4 border-t border-slate-800 text-xs text-slate-600 flex justify-between">
        <span>DeployForge v1.0 · Spring Boot + React · self-managed Kubernetes on AWS EC2</span>
        {error && <span className="text-red-500">⚠ {error}</span>}
        {loading && <span>Loading...</span>}
      </footer>
    </div>
  )
}
