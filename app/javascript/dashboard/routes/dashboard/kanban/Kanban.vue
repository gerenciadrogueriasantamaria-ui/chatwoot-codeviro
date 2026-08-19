<script setup>
import { computed, onMounted, onUnmounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import ConversationApi from 'dashboard/api/inbox/conversation';
import ConversationLabelsApi from 'dashboard/api/conversations';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const UNLABELED_COLUMN = {
  id: '__unlabeled__',
  title: 'Sin Etiqueta',
  color: '#64748B',
  isUnlabeled: true,
};

const REFRESH_INTERVAL_MS = 8000;

const store = useStore();
const router = useRouter();

const labels = useMapGetter('labels/getLabels');

const allConversations = ref([]);
const conversationsByColumn = ref({});
const isLoading = ref(false);
const movingConversationId = ref(null);
const draggedConversation = ref(null);
const draggedFromColumn = ref(null);
const refreshTimer = ref(null);
const isRefreshingSilently = ref(false);

const visibleLabels = computed(() => {
  return [...labels.value]
    .filter(label => label.show_on_sidebar)
    .sort((a, b) => a.title.localeCompare(b.title));
});

const columns = computed(() => {
  return [UNLABELED_COLUMN, ...visibleLabels.value];
});

const visibleLabelTitles = computed(() => {
  return visibleLabels.value.map(label => label.title);
});

const getConversationLabels = conversation => {
  return Array.isArray(conversation.labels) ? conversation.labels : [];
};

const getPrimaryColumnForConversation = conversation => {
  const currentLabels = getConversationLabels(conversation);
  const matchingLabel = visibleLabels.value.find(label =>
    currentLabels.includes(label.title)
  );

  return matchingLabel?.title || UNLABELED_COLUMN.id;
};

const groupConversations = conversations => {
  const grouped = columns.value.reduce((acc, column) => {
    acc[column.title] = [];
    return acc;
  }, {});

  grouped[UNLABELED_COLUMN.id] = [];

  conversations.forEach(conversation => {
    const columnKey = getPrimaryColumnForConversation(conversation);

    if (columnKey === UNLABELED_COLUMN.id) {
      grouped[UNLABELED_COLUMN.id].push(conversation);
    } else {
      grouped[columnKey].push(conversation);
    }
  });

  conversationsByColumn.value = grouped;
};

const fetchOpenConversations = async () => {
  const conversations = [];
  let page = 1;
  let keepLoading = true;

  while (keepLoading && page <= 10) {
    const response = await ConversationApi.get({
      status: 'open',
      assigneeType: 'all',
      page,
    });

    const payload = response.data?.data?.payload || [];
    conversations.push(...payload);

    keepLoading = payload.length > 0;
    page += 1;
  }

  return conversations;
};

const getConversationTitle = conversation => {
  return (
    conversation?.meta?.sender?.name ||
    conversation?.meta?.sender?.email ||
    conversation?.meta?.sender?.phone_number ||
    `Conversación #${conversation.id}`
  );
};

const getLastMessage = conversation => {
  const message = conversation?.messages?.[0];

  if (!message) return 'Sin mensajes';
  if (message.content) return message.content;
  if (message.attachments?.length) return 'Mensaje con adjunto';

  return 'Sin contenido';
};

const getAssigneeName = conversation => {
  return conversation?.meta?.assignee?.name || 'Sin asignar';
};

const getInboxName = conversation => {
  return conversation?.inbox?.name || conversation?.meta?.channel || 'Sin canal';
};

const getColumnColor = column => {
  return column?.color || UNLABELED_COLUMN.color;
};

const formatTimestamp = timestamp => {
  if (!timestamp) return '';

  const date = new Date(timestamp * 1000);
  return date.toLocaleString('es-CO', {
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
  });
};

const fetchBoard = async ({ silent = false } = {}) => {
  if (silent) {
    isRefreshingSilently.value = true;
  } else {
    isLoading.value = true;
  }

  try {
    await store.dispatch('labels/get');

    const conversations = await fetchOpenConversations();
    allConversations.value = conversations;
    groupConversations(conversations);
  } catch (error) {
    if (!silent) {
      useAlert('No se pudo cargar el tablero Kanban');
    }
  } finally {
    isLoading.value = false;
    isRefreshingSilently.value = false;
  }
};

const refreshBoardSilently = () => {
  if (isLoading.value || movingConversationId.value) return;

  fetchBoard({ silent: true });
};

const startAutoRefresh = () => {
  stopAutoRefresh();

  refreshTimer.value = window.setInterval(() => {
    if (document.hidden) return;

    refreshBoardSilently();
  }, REFRESH_INTERVAL_MS);
};

const stopAutoRefresh = () => {
  if (!refreshTimer.value) return;

  window.clearInterval(refreshTimer.value);
  refreshTimer.value = null;
};

const onWindowFocus = () => {
  refreshBoardSilently();
};

const onVisibilityChange = () => {
  if (!document.hidden) {
    refreshBoardSilently();
  }
};

const onDragStart = (conversation, column) => {
  draggedConversation.value = conversation;
  draggedFromColumn.value = column;
};

const onDragEnd = () => {
  draggedConversation.value = null;
  draggedFromColumn.value = null;
};

const getColumnKey = column => {
  return column.isUnlabeled ? UNLABELED_COLUMN.id : column.title;
};

const removeFromColumn = (columnKey, conversationId) => {
  conversationsByColumn.value = {
    ...conversationsByColumn.value,
    [columnKey]: (conversationsByColumn.value[columnKey] || []).filter(
      conversation => conversation.id !== conversationId
    ),
  };
};

const addToColumn = (columnKey, conversation) => {
  const currentColumn = conversationsByColumn.value[columnKey] || [];
  const alreadyExists = currentColumn.some(item => item.id === conversation.id);

  if (alreadyExists) return;

  conversationsByColumn.value = {
    ...conversationsByColumn.value,
    [columnKey]: [conversation, ...currentColumn],
  };
};

const buildNewLabels = (conversation, sourceColumn, targetColumn) => {
  const currentLabels = getConversationLabels(conversation);
  const sourceColumnKey = getColumnKey(sourceColumn);

  const labelsWithoutVisibleKanbanLabels = currentLabels.filter(label => {
    if (sourceColumnKey === UNLABELED_COLUMN.id) return true;

    return label !== sourceColumnKey;
  });

  if (targetColumn.isUnlabeled) {
    return currentLabels.filter(label => !visibleLabelTitles.value.includes(label));
  }

  return [...new Set([...labelsWithoutVisibleKanbanLabels, targetColumn.title])];
};

const replaceConversationInMemory = updatedConversation => {
  allConversations.value = allConversations.value.map(conversation => {
    if (conversation.id !== updatedConversation.id) return conversation;

    return updatedConversation;
  });
};

const onDrop = async targetColumn => {
  const conversation = draggedConversation.value;
  const sourceColumn = draggedFromColumn.value;

  if (!conversation || !sourceColumn) {
    onDragEnd();
    return;
  }

  const sourceKey = getColumnKey(sourceColumn);
  const targetKey = getColumnKey(targetColumn);

  if (sourceKey === targetKey) {
    onDragEnd();
    return;
  }

  const oldLabels = getConversationLabels(conversation);
  const newLabels = buildNewLabels(conversation, sourceColumn, targetColumn);
  const updatedConversation = {
    ...conversation,
    labels: newLabels,
  };

  movingConversationId.value = conversation.id;

  removeFromColumn(sourceKey, conversation.id);
  addToColumn(targetKey, updatedConversation);
  replaceConversationInMemory(updatedConversation);

  try {
    await ConversationLabelsApi.updateLabels(conversation.id, newLabels);
    useAlert(
      targetColumn.isUnlabeled
        ? 'Conversación movida a Sin Etiqueta'
        : `Conversación movida a ${targetColumn.title}`
    );
  } catch (error) {
    const revertedConversation = {
      ...conversation,
      labels: oldLabels,
    };

    removeFromColumn(targetKey, conversation.id);
    addToColumn(sourceKey, revertedConversation);
    replaceConversationInMemory(revertedConversation);

    useAlert('No se pudo mover la conversación');
  } finally {
    movingConversationId.value = null;
    onDragEnd();
  }
};

const openConversation = conversation => {
  router.push({
    name: 'inbox_conversation',
    params: {
      conversation_id: conversation.id,
    },
  });
};

onMounted(() => {
  fetchBoard();
  startAutoRefresh();

  window.addEventListener('focus', onWindowFocus);
  document.addEventListener('visibilitychange', onVisibilityChange);
});

onUnmounted(() => {
  stopAutoRefresh();

  window.removeEventListener('focus', onWindowFocus);
  document.removeEventListener('visibilitychange', onVisibilityChange);
});
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-background">
    <header class="px-8 py-6 border-b border-n-weak">
      <div class="flex items-center justify-between gap-4">
        <div>
          <h1 class="m-0 text-xl font-semibold text-n-slate-12">
            Kanban
          </h1>
          <p class="mt-1 mb-0 text-sm text-n-slate-11">
            Organiza las conversaciones por etiqueta.
          </p>
        </div>

        <button
          type="button"
          class="h-9 px-4 rounded-lg text-sm font-medium text-white bg-n-brand hover:bg-n-brand/90 disabled:opacity-60"
          :disabled="isLoading"
          @click="fetchBoard()"
        >
          Actualizar
        </button>
      </div>
    </header>

    <main class="flex-1 overflow-hidden">
      <div v-if="isLoading" class="flex items-center justify-center h-full">
        <Spinner class="text-n-brand" />
      </div>

      <div
        v-else
        class="flex h-full gap-4 px-8 py-6 overflow-x-auto overflow-y-hidden"
      >
        <section
          v-for="column in columns"
          :key="getColumnKey(column)"
          class="flex flex-col flex-shrink-0 w-[320px] max-h-full rounded-xl border border-n-weak bg-n-alpha-1"
          @dragover.prevent
          @drop="onDrop(column)"
        >
          <header class="flex items-center justify-between gap-3 px-4 py-3 border-b border-n-weak">
            <div class="flex items-center min-w-0 gap-2">
              <span
                class="flex-shrink-0 size-2.5 rounded-sm"
                :style="{ backgroundColor: column.color }"
              />
              <h2 class="m-0 text-sm font-semibold truncate text-n-slate-12">
                {{ column.title }}
              </h2>
            </div>

            <span class="px-2 py-0.5 rounded-md text-xs font-medium text-n-slate-11 bg-n-alpha-2">
              {{ conversationsByColumn[getColumnKey(column)]?.length || 0 }}
            </span>
          </header>

          <div class="flex-1 p-3 overflow-y-auto">
            <article
  v-for="conversation in conversationsByColumn[getColumnKey(column)] || []"
  :key="conversation.id"
  draggable="true"
  class="p-3 mb-3 transition-colors border rounded-lg cursor-grab border-n-weak bg-n-solid-1 hover:bg-n-alpha-2 active:cursor-grabbing"
  :class="{
    'opacity-50 pointer-events-none': movingConversationId === conversation.id,
  }"
  @dragstart="onDragStart(conversation, column)"
  @dragend="onDragEnd"
>
  <div class="flex items-start justify-between gap-2">
    <h3 class="m-0 text-sm font-semibold leading-5 text-n-slate-12 line-clamp-2">
      {{ getConversationTitle(conversation) }}
    </h3>

    <span class="flex-shrink-0 text-xs text-n-slate-10">
      #{{ conversation.id }}
    </span>
  </div>

  <div class="flex items-center gap-2 mt-2 text-xs text-n-slate-10">
    <span
      class="flex-shrink-0 size-2 rounded-sm"
      :style="{ backgroundColor: getColumnColor(column) }"
    />
    <span class="truncate">
      {{ getInboxName(conversation) }}
    </span>
  </div>

  <p class="mt-2 mb-0 text-sm leading-5 text-n-slate-11 line-clamp-2">
    {{ getLastMessage(conversation) }}
  </p>

  <footer class="flex items-center justify-between gap-3 mt-3 text-xs text-n-slate-10">
    <span class="truncate">
      {{ getAssigneeName(conversation) }}
    </span>
    <span class="flex-shrink-0">
      {{ formatTimestamp(conversation.timestamp) }}
    </span>
  </footer>

  <button
    type="button"
    class="w-full h-8 mt-3 rounded-md text-xs font-semibold text-white transition-opacity hover:opacity-90"
    :style="{ backgroundColor: getColumnColor(column) }"
    @click.stop="openConversation(conversation)"
  >
    Ir a la conversación
  </button>
</article>

            <div
              v-if="!(conversationsByColumn[getColumnKey(column)] || []).length"
              class="flex items-center justify-center h-28 rounded-lg border border-dashed border-n-weak text-sm text-n-slate-10"
            >
              Sin conversaciones
            </div>
          </div>
        </section>
      </div>
    </main>
  </section>
</template>
