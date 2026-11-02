<script setup>
// 錯誤訊息＝看得懂的原因＋追蹤編號；使用者回報追蹤編號，維運拿去搜 log（Module 5）
defineProps({ error: Object })
</script>

<template>
  <div v-if="error" class="error-box" role="alert">
    <strong>{{ error.message }}</strong>
    <span v-if="error.detail">{{ error.detail }}</span>
    <ul v-if="error.errors">
      <li v-for="(msgs, field) in error.errors" :key="field">{{ msgs.join('、') }}</li>
    </ul>
    <small v-if="error.traceId">追蹤編號 <code>{{ error.traceId }}</code>（回報問題時請附上）</small>
  </div>
</template>
