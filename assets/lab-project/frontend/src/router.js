import { createRouter, createWebHistory } from 'vue-router'
import { session, api } from './api.js'
import LoginView from './views/LoginView.vue'
import DeploymentsView from './views/DeploymentsView.vue'
import UsersView from './views/UsersView.vue'
import AuditView from './views/AuditView.vue'
import SystemView from './views/SystemView.vue'

export const router = createRouter({
  history: createWebHistory(),
  routes: [
    { path: '/login', component: LoginView, meta: { public: true } },
    { path: '/', component: DeploymentsView },
    { path: '/users', component: UsersView, meta: { role: 'Admin' } },
    { path: '/audit', component: AuditView, meta: { role: 'Admin' } },
    { path: '/system', component: SystemView, meta: { public: true } },
  ],
})

let checked = false
router.beforeEach(async (to) => {
  if (!checked) {
    checked = true
    session.user = await api('/api/auth/me').catch(() => null)
  }
  if (to.meta.public) return true
  if (!session.user) return { path: '/login', query: { next: to.fullPath } }
  if (to.meta.role && session.user.role !== to.meta.role) return '/'
  return true
})
