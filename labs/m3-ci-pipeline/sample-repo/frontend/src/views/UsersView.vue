<script setup>
import { ref, onMounted } from 'vue'
import { api, session, roleLabel, fmtTime } from '../api.js'
import ErrorBox from './ErrorBox.vue'

const users = ref([])
const error = ref(null)
const form = ref({ userName: '', displayName: '', role: 'Viewer', password: '' })
const formError = ref(null)

async function load() {
  try {
    users.value = await api('/api/users')
  } catch (e) {
    error.value = e
  }
}
onMounted(load)

async function update(u, patch) {
  error.value = null
  try {
    await api(`/api/users/${u.id}`, { method: 'PUT', body: { displayName: u.displayName, role: u.role, isActive: u.isActive, ...patch } })
  } catch (e) {
    error.value = e
  }
  await load()
}
async function create() {
  formError.value = null
  try {
    await api('/api/users', { method: 'POST', body: form.value })
    form.value = { userName: '', displayName: '', role: 'Viewer', password: '' }
    await load()
  } catch (e) {
    formError.value = e
  }
}
</script>

<template>
  <section>
    <h1>帳號管理</h1>
    <ErrorBox :error="error" />
    <table>
      <thead><tr><th>帳號</th><th>名稱</th><th>角色</th><th>狀態</th><th>建立時間</th></tr></thead>
      <tbody>
        <tr v-for="u in users" :key="u.id" :class="{ inactive: !u.isActive }">
          <td class="mono">{{ u.userName }}</td>
          <td>{{ u.displayName }}</td>
          <td>
            <select :value="u.role" :disabled="u.userName === session.user.userName" @change="update(u, { role: $event.target.value })">
              <option v-for="(label, r) in roleLabel" :key="r" :value="r">{{ label }}</option>
            </select>
          </td>
          <td>
            <label class="switch">
              <input type="checkbox" :checked="u.isActive" :disabled="u.userName === session.user.userName" @change="update(u, { isActive: $event.target.checked })" />
              {{ u.isActive ? '啟用' : '停用' }}
            </label>
          </td>
          <td class="mono">{{ fmtTime(u.createdAt) }}</td>
        </tr>
      </tbody>
    </table>

    <h2>新增帳號</h2>
    <form class="inline-form" @submit.prevent="create">
      <input v-model.trim="form.userName" placeholder="帳號" required maxlength="50" />
      <input v-model.trim="form.displayName" placeholder="顯示名稱" required maxlength="50" />
      <select v-model="form.role"><option v-for="(label, r) in roleLabel" :key="r" :value="r">{{ label }}</option></select>
      <input v-model="form.password" type="password" placeholder="初始密碼（至少 8 碼）" required autocomplete="new-password" />
      <button>新增</button>
    </form>
    <ErrorBox :error="formError" />
  </section>
</template>
