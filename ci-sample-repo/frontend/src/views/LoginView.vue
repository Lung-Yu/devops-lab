<script setup>
import { ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { api, session } from '../api.js'
import ErrorBox from './ErrorBox.vue'

const route = useRoute()
const router = useRouter()
const form = ref({ userName: '', password: '' })
const error = ref(null)
const busy = ref(false)

async function submit() {
  busy.value = true
  error.value = null
  try {
    session.user = await api('/api/auth/login', { method: 'POST', body: form.value })
    router.push(route.query.next || '/')
  } catch (e) {
    error.value = e
  } finally {
    busy.value = false
  }
}
</script>

<template>
  <section class="login">
    <h1>登入</h1>
    <form @submit.prevent="submit">
      <label>帳號<input v-model.trim="form.userName" autocomplete="username" required autofocus /></label>
      <label>密碼<input v-model="form.password" type="password" autocomplete="current-password" required /></label>
      <button :disabled="busy">{{ busy ? '登入中…' : '登入' }}</button>
    </form>
    <ErrorBox :error="error" />
    <p class="hint">課堂帳號：<code>admin</code>／<code>engineer</code>／<code>viewer</code>，密碼見 Lab 手冊</p>
  </section>
</template>
