<script setup>
import { computed, onMounted, onUnmounted, ref, watch } from 'vue';
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

const PAGE_SIZE = 100;
const LOAD_MORE_OFFSET = 120;

const store = useStore();
const router = useRouter();

const inboxes = useMapGetter('inboxes/getInboxes');
const labels = useMapGetter('labels/getLabels');

const conversationsByColumn = ref({});
const columnTotals = ref({});
const columnPages = ref({});
const columnHasMore = ref({});
const columnLoading = ref({});
const isLoading = ref(false);
const movingConversationId = ref(null);
const draggedConversation = ref(null);
const draggedFromColumn = ref(null);
const isRefreshingSilently = ref(false);
const selectedInboxId = ref('all');
const searchQuery = ref('');
let searchTimer = null;

const visibleLabels = computed(() => {
  return [...(labels.value || [])]
    .filter(label => label.show_on_sidebar)
    .sort((a, b) => a.title.localeCompare(b.title));
});

const columns = computed(() => {
  return [UNLABELED_COLUMN, ...visibleLabels.value];
});

const sortedInboxes = computed(() => {
  return [...(inboxes.value || [])].sort((a, b) =>
    a.name.localeCompare(b.name)
  );
});

const inboxFilters = computed(() => {
  return [
    {
      id: 'all',
      name: 'Todos',
    },
    ...sortedInboxes.value,
  ];
});

const selectedInboxName = computed(() => {
  if (selectedInboxId.value === 'all') return 'Todos los canales';

  const inbox = sortedInboxes.value.find(
    item => String(item.id) === String(selectedInboxId.value)
  );

  return inbox?.name || 'Canal seleccionado';
});

const visibleLabelTitles = computed(() => {
  return visibleLabels.value.map(label => label.title);
});

const getColumnKey = column => {
  return column.isUnlabeled ? UNLABELED_COLUMN.id : column.title;
};

const getConversationLabels = conversation => {
  return Array.isArray(conversation.labels) ? conversation.labels : [];
};

const getColumnColor = column => {
  return column?.color || UNLABELED_COLUMN.color;
};

const getStatusLabel = conversation => {
  return conversation.status === 'resolved' ? 'Cerrada' : 'Abierta';
};

const getStatusClasses = conversation => {
  return conversation.status === 'resolved'
    ? 'text-green-300 bg-green-900/30'
    : 'text-blue-300 bg-blue-900/30';
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
  const inboxId = Number(conversation?.inbox_id || conversation?.inbox?.id);
  const inbox = (inboxes.value || []).find(item => Number(item.id) === inboxId);

  return inbox?.name || conversation?.inbox?.name || 'Sin canal';
};

const getContactPhone = conversation => {
  return (
    conversation?.meta?.sender?.phone_number ||
    conversation?.meta?.sender?.identifier ||
    conversation?.contact?.phone_number ||
    conversation?.contact?.identifier ||
    conversation?.contact_inbox?.source_id ||
    conversation?.source_id ||
    ''
  );
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

const resetColumnState = () => {
  const conversations = {};
  const totals = {};
  const pages = {};
  const hasMore = {};
  const loading = {};

  columns.value.forEach(column => {
    const key = getColumnKey(column);
    conversations[key] = [];
    totals[key] = 0;
    pages[key] = 0;
    hasMore[key] = true;
    loading[key] = false;
  });

  conversationsByColumn.value = conversations;
  columnTotals.value = totals;
  columnPages.value = pages;
  columnHasMore.value = hasMore;
  columnLoading.value = loading;
};

const fetchKanbanColumn = async (column, page = 1, { append = false } = {}) => {
  const columnKey = getColumnKey(column);

  if (columnLoading.value[columnKey]) return;

  columnLoading.value = {
    ...columnLoading.value,
    [columnKey]: true,
  };

  try {
    const response = await ConversationApi.kanban({
  column: columnKey,
  inboxId: selectedInboxId.value === 'all' ? undefined : selectedInboxId.value,
  search: searchQuery.value.trim() || undefined,
  page,
  perPage: PAGE_SIZE,
});

    const payload = response.data?.payload || [];
    const total = response.data?.total || 0;

    conversationsByColumn.value = {
      ...conversationsByColumn.value,
      [columnKey]: append
        ? [...(conversationsByColumn.value[columnKey] || []), ...payload]
        : payload,
    };

    columnTotals.value = {
      ...columnTotals.value,
      [columnKey]: total,
    };

    columnPages.value = {
      ...columnPages.value,
      [columnKey]: page,
    };

    columnHasMore.value = {
      ...columnHasMore.value,
      [columnKey]: page * PAGE_SIZE < total,
    };
  } catch (error) {
    useAlert('No se pudo cargar una columna del Kanban');
  } finally {
    columnLoading.value = {
      ...columnLoading.value,
      [columnKey]: false,
    };
  }
};

const fetchBoard = async ({ silent = false } = {}) => {
  if (silent) {
    isRefreshingSilently.value = true;
  } else {
    isLoading.value = true;
  }

  try {
    await Promise.all([
      store.dispatch('labels/get'),
      store.dispatch('inboxes/get'),
    ]);

    resetColumnState();

    await Promise.all(
      columns.value.map(column => fetchKanbanColumn(column, 1))
    );
  } catch (error) {
    if (!silent) {
      useAlert('No se pudo cargar el tablero Kanban');
    }
  } finally {
    isLoading.value = false;
    isRefreshingSilently.value = false;
  }
};

const loadMoreColumn = async column => {
  const columnKey = getColumnKey(column);

  if (!columnHasMore.value[columnKey] || columnLoading.value[columnKey]) return;

  await fetchKanbanColumn(column, (columnPages.value[columnKey] || 1) + 1, {
    append: true,
  });
};

const onColumnScroll = (event, column) => {
  const target = event.target;
  const distanceToBottom =
    target.scrollHeight - target.scrollTop - target.clientHeight;

  if (distanceToBottom <= LOAD_MORE_OFFSET) {
    loadMoreColumn(column);
  }
};

const refreshBoardSilently = () => {
  if (isLoading.value || movingConversationId.value) return;

  fetchBoard({ silent: true });
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

const removeFromColumn = (columnKey, conversationId) => {
  conversationsByColumn.value = {
    ...conversationsByColumn.value,
    [columnKey]: (conversationsByColumn.value[columnKey] || []).filter(
      conversation => conversation.id !== conversationId
    ),
  };

  columnTotals.value = {
    ...columnTotals.value,
    [columnKey]: Math.max((columnTotals.value[columnKey] || 0) - 1, 0),
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

  columnTotals.value = {
    ...columnTotals.value,
    [columnKey]: (columnTotals.value[columnKey] || 0) + 1,
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
    return currentLabels.filter(
      label => !visibleLabelTitles.value.includes(label)
    );
  }

  return [...new Set([...labelsWithoutVisibleKanbanLabels, targetColumn.title])];
};

const replaceConversationInMemory = updatedConversation => {
  Object.keys(conversationsByColumn.value).forEach(columnKey => {
    conversationsByColumn.value = {
      ...conversationsByColumn.value,
      [columnKey]: (conversationsByColumn.value[columnKey] || []).map(
        conversation => {
          if (conversation.id !== updatedConversation.id) return conversation;

          return updatedConversation;
        }
      ),
    };
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

const selectInbox = inboxId => {
  selectedInboxId.value = inboxId;
  fetchBoard();
};

watch(searchQuery, () => {
  clearTimeout(searchTimer);

  searchTimer = setTimeout(() => {
    fetchBoard();
  }, 350);
});

onMounted(() => {
  fetchBoard();

  window.addEventListener('focus', onWindowFocus);
  document.addEventListener('visibilitychange', onVisibilityChange);
});

onUnmounted(() => {
  clearTimeout(searchTimer);

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
            Organiza las conversaciones abiertas y cerradas por etiqueta.
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

    <nav class="px-8 pt-4 border-b border-n-weak">
      <div class="flex items-center gap-3 mb-3">
        <span class="text-sm font-medium text-n-slate-11">
          Canales
        </span>
        <span class="text-xs text-n-slate-10">
          {{ selectedInboxName }}
        </span>
      </div>

      <div class="flex gap-2 pb-4 overflow-x-auto">
  <button
    v-for="inbox in inboxFilters"
    :key="inbox.id"
    type="button"
    class="flex items-center flex-shrink-0 gap-2 px-3 py-2 text-sm rounded-lg transition-colors"
    :class="
      String(selectedInboxId) === String(inbox.id)
        ? 'text-n-slate-12 bg-n-alpha-2 font-semibold'
        : 'text-n-slate-11 hover:text-n-slate-12 hover:bg-n-alpha-1'
    "
    @click="selectInbox(inbox.id)"
  >
    <span class="text-n-slate-10">
      {}
    </span>
    <span class="max-w-[180px] truncate">
      {{ inbox.name }}
    </span>
  </button>
</div>

<div class="flex items-center w-full max-w-sm h-9 px-3 mt-4 mb-4 rounded-lg bg-n-alpha-2">
  <fluent-icon
    icon="search"
    size="16"
    class="flex-shrink-0 mr-2 text-n-slate-10"
  />
  <input
  v-model="searchQuery"
  type="text"
  class="kanban-search-input flex-1 min-w-0 w-full h-full text-sm leading-9 bg-transparent text-n-slate-12 placeholder:text-n-slate-10"
  placeholder="Buscar por nombre o celular"
/>
</div>
</nav>

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
              {{ columnTotals[getColumnKey(column)] || 0 }}
            </span>
          </header>

          <div
            class="flex-1 p-3 overflow-y-auto"
            @scroll="onColumnScroll($event, column)"
          >
            <article
              v-for="conversation in conversationsByColumn[getColumnKey(column)] || []"
              :key="conversation.id"
              draggable="true"
              class="p-3 mb-3 transition-colors border rounded-lg cursor-grab border-n-weak bg-n-solid-1 hover:bg-n-alpha-2 active:cursor-grabbing"
              :class="{
                'opacity-50 pointer-events-none':
                  movingConversationId === conversation.id,
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

              <div class="flex items-center justify-between gap-2 mt-2">
                <div class="flex items-center min-w-0 gap-2 text-xs text-n-slate-10">
                  <span
                    class="flex-shrink-0 size-2 rounded-sm"
                    :style="{ backgroundColor: getColumnColor(column) }"
                  />
                  <span class="truncate">
                    {{ getInboxName(conversation) }}
                  </span>
                </div>

                <span
                  class="flex-shrink-0 px-2 py-0.5 rounded-md text-[11px] font-semibold"
                  :class="getStatusClasses(conversation)"
                >
                  {{ getStatusLabel(conversation) }}
                </span>
              </div>

              <p
  v-if="getContactPhone(conversation)"
  class="mt-2 mb-0 text-xs text-n-slate-10 truncate"
>
  {{ getContactPhone(conversation) }}
              </p>

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
              v-if="!(conversationsByColumn[getColumnKey(column)] || []).length && !columnLoading[getColumnKey(column)]"
              class="flex items-center justify-center h-28 rounded-lg border border-dashed border-n-weak text-sm text-n-slate-10"
            >
              Sin conversaciones
            </div>

            <div
              v-if="columnLoading[getColumnKey(column)] && !isLoading"
              class="flex items-center justify-center py-4"
            >
              <Spinner class="text-n-brand" />
            </div>

            <div
              v-if="!columnHasMore[getColumnKey(column)] && (conversationsByColumn[getColumnKey(column)] || []).length"
              class="py-3 text-xs text-center text-n-slate-10"
            >
              Todas las conversaciones cargadas
            </div>
          </div>
        </section>
      </div>
    </main>
  </section>
</template>

<style scoped>
:deep(.kanban-search-input) {
  width: 100%;
  height: 100%;
  padding: 0 !important;
  margin: 0 !important;
  color: rgb(var(--slate-12));
  background: transparent !important;
  border: 0 !important;
  border-radius: 0 !important;
  box-shadow: none !important;
  outline: 0 !important;
}

:deep(.kanban-search-input:focus) {
  background: transparent !important;
  border: 0 !important;
  box-shadow: none !important;
  outline: 0 !important;
}
</style>
