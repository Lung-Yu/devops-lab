<script setup>
import { onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { session, api, can, roleLabel } from './api.js'

const router = useRouter()
onMounted(async () => {
  session.system = await api('/api/system').catch(() => null)
})

async function logout() {
  await api('/api/auth/logout', { method: 'POST' })
  session.user = null
  router.push('/login')
}

// 環境色條：一眼看出現在連的是哪個環境，避免把 POC 當成 Dev 亂操作
const envClass = (env) => ({ Development: 'env-dev', QA: 'env-qa', POC: 'env-poc', Production: 'env-prod' })[env] || 'env-other'
</script>

<template>
  <div class="env-strip" :class="envClass(session.system?.environment)">
    <span>環境：<b>{{ session.system?.environment ?? '未知' }}</b></span>
    <span class="mono">v{{ session.system?.version ?? '?' }}</span>
  </div>
  <header class="topbar">
    <RouterLink to="/" class="brand">DeployLog<small>部署紀錄</small></RouterLink>
    <nav v-if="session.user">
      <RouterLink to="/">部署紀錄</RouterLink>
      <RouterLink v-if="can.admin()" to="/users">帳號管理</RouterLink>
      <RouterLink v-if="can.admin()" to="/audit">稽核紀錄</RouterLink>
      <RouterLink to="/system">系統狀態</RouterLink>
    </nav>
    <div v-if="session.user" class="who">
      <span>{{ session.user.displayName }}</span>
      <span class="role" :data-role="session.user.role">{{ roleLabel[session.user.role] }}</span>
      <button class="ghost" @click="logout">登出</button>
    </div>
  </header>
  <main>
    <RouterView />
  </main>
</template>
