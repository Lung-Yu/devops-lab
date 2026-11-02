import { reactive } from 'vue'

// 目前登入者（null = 未登入）。權限判斷只用來決定「要不要顯示按鈕」，真正的把關在後端
export const session = reactive({ user: null, system: null })

export const can = {
  edit: () => ['Admin', 'Engineer'].includes(session.user?.role),
  admin: () => session.user?.role === 'Admin',
}

// 後端錯誤一律是 Problem Details（title／detail／traceId），畫面直接顯示
export class ApiError extends Error {
  constructor(status, problem) {
    super(problem?.title || `HTTP ${status}`)
    this.status = status
    this.detail = problem?.detail
    this.traceId = problem?.traceId
    this.errors = problem?.errors
  }
}

export async function api(path, { method = 'GET', body } = {}) {
  const res = await fetch(path, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
    credentials: 'same-origin',
  })
  if (res.status === 401 && session.user && path !== '/api/auth/login') {
    session.user = null   // cookie 過期或帳號被停用
  }
  if (!res.ok) {
    const problem = res.headers.get('content-type')?.includes('json') ? await res.json() : null
    throw new ApiError(res.status, { traceId: res.headers.get('X-Trace-Id'), ...problem })
  }
  return res.status === 204 ? null : res.json()
}

export const statusLabel = {
  Planned: '已排程', Deploying: '部署中', Succeeded: '成功', Failed: '失敗', RolledBack: '已回滾',
}
export const roleLabel = { Admin: '管理員', Engineer: '工程師', Viewer: '檢視者' }

export function fmtTime(iso) {
  return new Date(iso).toLocaleString('zh-TW', { hour12: false, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
}
