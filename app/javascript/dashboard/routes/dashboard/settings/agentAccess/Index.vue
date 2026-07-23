<script setup>
import { computed, onMounted, ref } from 'vue';
import SettingsLayout from '../SettingsLayout.vue';
import agentAccessPoliciesAPI from 'dashboard/api/agentAccessPolicies';

const days = [
  { key: '1', label: 'Lunes' },
  { key: '2', label: 'Martes' },
  { key: '3', label: 'Miércoles' },
  { key: '4', label: 'Jueves' },
  { key: '5', label: 'Viernes' },
];

const hours = Array.from({ length: 24 }, (_, index) => index);
const sessionOptions = Array.from({ length: 11 }, (_, index) => index);

const users = ref([]);
const selectedUserId = ref(null);
const policy = ref({
  enabled: true,
  max_sessions: 1,
  schedule: {},
});
const sessions = ref([]);
const isLoading = ref(false);
const isSaving = ref(false);

const selectedUser = computed(() =>
  users.value.find(user => Number(user.id) === Number(selectedUserId.value))
);

const normalizeSchedule = schedule => {
  const normalized = {};

  days.forEach(day => {
    normalized[day.key] = {};
    hours.forEach(hour => {
      normalized[day.key][String(hour)] = schedule?.[day.key]?.[String(hour)] === true;
    });
  });

  return normalized;
};

const loadUsers = async () => {
  isLoading.value = true;

  try {
    const response = await agentAccessPoliciesAPI.getUsers();
    users.value = response.data.users || [];

    if (users.value.length) {
      selectedUserId.value = users.value[0].id;
      await loadPolicy();
    }
  } finally {
    isLoading.value = false;
  }
};

const loadPolicy = async () => {
  if (!selectedUserId.value) return;

  isLoading.value = true;

  try {
    const response = await agentAccessPoliciesAPI.getPolicy(selectedUserId.value);
    policy.value = {
      enabled: response.data.policy.enabled,
      max_sessions: response.data.policy.max_sessions,
      schedule: normalizeSchedule(response.data.policy.schedule),
    };
    sessions.value = response.data.sessions || [];
  } finally {
    isLoading.value = false;
  }
};

const toggleHour = (dayKey, hour) => {
  const hourKey = String(hour);
  policy.value.schedule[dayKey][hourKey] = !policy.value.schedule[dayKey][hourKey];
};

const isHourEnabled = (dayKey, hour) => {
  return policy.value.schedule?.[dayKey]?.[String(hour)] === true;
};

  const formatColombiaDateTime = value => {
  if (!value) return 'N/A';

  return new Intl.DateTimeFormat('es-CO', {
    timeZone: 'America/Bogota',
    dateStyle: 'short',
    timeStyle: 'short',
  }).format(new Date(value));
};

const savePolicy = async () => {
  if (!selectedUserId.value) return;

  isSaving.value = true;

  try {
    const response = await agentAccessPoliciesAPI.updatePolicy(selectedUserId.value, {
      enabled: policy.value.enabled,
      max_sessions: policy.value.max_sessions,
      schedule: policy.value.schedule,
    });

    policy.value = {
      enabled: response.data.policy.enabled,
      max_sessions: response.data.policy.max_sessions,
      schedule: normalizeSchedule(response.data.policy.schedule),
    };
    sessions.value = response.data.sessions || [];
  } finally {
    isSaving.value = false;
  }
};

const revokeSession = async sessionId => {
  if (!selectedUserId.value) return;

  const response = await agentAccessPoliciesAPI.deleteSession(
    selectedUserId.value,
    sessionId
  );

  sessions.value = response.data.sessions || [];
};

onMounted(loadUsers);
</script>

<template>
  <SettingsLayout :is-loading="isLoading && !users.length">
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
      <div class="flex flex-col gap-5 w-full">
        <section class="grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_280px] gap-4">
          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <label class="block text-sm font-medium text-n-slate-12 mb-2">
              Agente o supervisor
            </label>
            <select
              v-model="selectedUserId"
              class="w-full h-10 rounded-md border border-n-weak bg-n-alpha-2 px-3 text-sm text-n-slate-12"
              @change="loadPolicy"
            >
              <option
                v-for="user in users"
                :key="user.id"
                :value="user.id"
              >
                {{ user.name }} - {{ user.email }} ({{ user.role }})
              </option>
            </select>
          </div>

          <div class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
            <label class="block text-sm font-medium text-n-slate-12 mb-2">
              Sesiones activas permitidas
            </label>
            <select
              v-model.number="policy.max_sessions"
              class="w-full h-10 rounded-md border border-n-weak bg-n-alpha-2 px-3 text-sm text-n-slate-12"
            >
              <option
                v-for="option in sessionOptions"
                :key="option"
                :value="option"
              >
                {{ option }}
              </option>
            </select>
          </div>
        </section>

        <section class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
          <div class="flex items-center justify-between gap-3 mb-4">
            <div>
              <h2 class="text-base font-semibold text-n-slate-12">
                Horario permitido
              </h2>
              <p class="text-sm text-n-slate-11">
                Haz clic en las horas donde {{ selectedUser?.name || 'el usuario' }} puede ingresar.
              </p>
            </div>

            <label class="flex items-center gap-2 text-sm text-n-slate-12">
              <input
                v-model="policy.enabled"
                type="checkbox"
              />
              Política activa
            </label>
          </div>

          <div class="overflow-x-auto">
            <div class="grid min-w-[920px] grid-cols-[88px_repeat(5,minmax(120px,1fr))] gap-1">
              <div />
              <div
                v-for="day in days"
                :key="day.key"
                class="text-center text-xs font-semibold text-n-slate-11 py-2"
              >
                {{ day.label }}
              </div>

              <template
                v-for="hour in hours"
                :key="hour"
              >
                <div class="h-9 flex items-center justify-end pr-3 text-xs font-semibold text-n-slate-11">
                  {{ String(hour).padStart(2, '0') }}:00
                </div>

                <button
                  v-for="day in days"
                  :key="`${day.key}-${hour}`"
                  type="button"
                  class="h-9 rounded border border-n-weak transition-colors"
                  :class="
                    isHourEnabled(day.key, hour)
                    ? 'bg-[#1f93ff] hover:bg-[#1a7edb] border-[#1f93ff]'
                    : 'bg-n-alpha-2 hover:bg-n-alpha-3'
                  "
                  @click="toggleHour(day.key, hour)"
                />
              </template>
            </div>
          </div>
        </section>

        <section class="rounded-lg border border-n-weak bg-n-solid-1 p-4">
          <div class="flex items-center justify-between mb-3">
            <h2 class="text-base font-semibold text-n-slate-12">
              Sesiones activas
            </h2>
            <button
  type="button"
  class="h-9 rounded-md bg-[#1f93ff] px-4 text-sm font-semibold text-white transition-colors hover:bg-[#1a7edb] disabled:cursor-not-allowed disabled:opacity-60"
  :disabled="isSaving"
  @click="savePolicy"
>
  {{ isSaving ? 'Guardando...' : 'Guardar cambios' }}
</button>
          </div>

          <div
            v-if="!sessions.length"
            class="text-sm text-n-slate-11 py-4"
          >
            No hay sesiones activas para este usuario.
          </div>

          <div
            v-for="session in sessions"
            :key="session.id"
            class="flex items-center justify-between gap-3 border-t border-n-weak py-3"
          >
            <div class="min-w-0">
              <p class="text-sm font-medium text-n-slate-12 truncate">
                {{ session.user_agent || 'Dispositivo sin identificar' }}
              </p>
              <p class="text-xs text-n-slate-11">
                IP {{ session.ip_address || 'N/A' }} · Última actividad {{ formatColombiaDateTime(session.last_seen_at) }}
              </p>
            </div>

            <button
              type="button"
              class="h-9 rounded-md bg-[#1f93ff] px-4 text-sm font-semibold text-white transition-colors hover:bg-[#1a7edb]"
              @click="revokeSession(session.id)"
            >
              Cerrar
            </button>
          </div>
        </section>
      </div>
    </template>
  </SettingsLayout>
</template>
