<script setup>
import SettingsLayout from '../SettingsLayout.vue';
</script>

<template>
  <SettingsLayout>
    <template #header>
      <div class="flex flex-col gap-1">
        <h1 class="text-xl font-semibold text-n-slate-12">
          Control de acceso
        </h1>
        <p class="text-sm text-n-slate-11">
          Configura horarios permitidos, límite de sesiones y sesiones activas por agente.
        </p>
      </div>
    </template>

    <template #body>
      <section class="rounded-lg border border-n-weak bg-n-solid-1 p-6">
        <p class="text-sm text-n-slate-11">
          Página de control de acceso lista para conectar.
        </p>
      </section>
    </template>
  </SettingsLayout>
</template>
