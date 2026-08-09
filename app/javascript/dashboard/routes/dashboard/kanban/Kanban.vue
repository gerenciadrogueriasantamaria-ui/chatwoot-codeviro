<script setup>
import { computed, onMounted, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useAlert } from 'dashboard/composables';

import ConversationApi from 'dashboard/api/inbox/conversation';
import ConversationLabelsApi from 'dashboard/api/conversations';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const store = useStore();
const router = useRouter();

const labels = useMapGetter('labels/getLabels');

const conversationsByLabel = ref({});
const isLoading = ref(false);
const movingConversationId = ref(null);
const draggedConversation = ref(null);
const draggedFromLabel = ref(null);

const visibleLabels = computed(() => {
  return [...labels.value]
    .filter(label => label.show_on_sidebar)
    .sort((a, b) => a.title.localeCompare(b.title));
});

const buildFilterPayload = labelTitle => {
  return {
    page: 1,
    queryData: {
      payload: [
        {
          attribute_key: 'labels',
          filter_operator: 'equal_to',
          values: [labelTitle],
          query_operator: 'and',
        },
      ],
    },
  };
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

const fetchColumn = async label => {
  const response = await ConversationApi.filter(buildFilterPayload(label.title));
  conversationsByLabel.value = {
    ...conversationsByLabel.value,
    [label.title]: response.data.payload || [],
  };
};

const fetchBoard = async () => {
  isLoading.value = true;

  try {
    await store.dispatch('labels/get');

    await Promise.all(
      visibleLabels.value.map(label => {
        return fetchColumn(label);
      })
    );
  } catch (error) {
    useAlert('No se pudo cargar el tablero Kanban');
  } finally {
    isLoading.value = false;
  }
};

const onDragStart = (conversation, labelTitle) => {
  draggedConversation.value = conversation;
  draggedFromLabel.value = labelTitle;
};

const onDragEnd = () => {
  draggedConversation.value = null;
  draggedFromLabel.value = null;
};

const removeFromColumn = (labelTitle, conversationId) => {
  conversationsByLabel.value = {
    ...conversationsByLabel.value,
    [labelTitle]: (conversationsByLabel.value[labelTitle] || []).filter(
      conversation => conversation.id !== conversationId
    ),
  };
};

const addToColumn = (labelTitle, conversation) => {
  const currentColumn = conversationsByLabel.value[labelTitle] || [];
  const alreadyExists = currentColumn.some(item => item.id === conversation.id);

  if (alreadyExists) return;

  conversationsByLabel.value = {
    ...conversationsByLabel.value,
    [labelTitle]: [
      {
        ...conversation,
        labels: [
          ...conversation.labels.filter(label => label !== draggedFromLabel.value),
          labelTitle,
        ],
      },
      ...currentColumn,
    ],
  };
};

const onDrop = async targetLabel => {
  const conversation = draggedConversation.value;
  const sourceLabel = draggedFromLabel.value;

  if (!conversation || !sourceLabel || sourceLabel === targetLabel.title) {
    onDragEnd();
    return;
  }

  const oldLabels = conversation.labels || [];
  const newLabels = [
    ...oldLabels.filter(label => label !== sourceLabel),
    targetLabel.title,
  ];

  movingConversationId.value = conversation.id;

  removeFromColumn(sourceLabel, conversation.id);
  addToColumn(targetLabel.title, {
    ...conversation,
    labels: newLabels,
  });

  try {
    await ConversationLabelsApi.updateLabels(conversation.id, newLabels);
    useAlert(`Conversación movida a ${targetLabel.title}`);
  } catch (error) {
    removeFromColumn(targetLabel.title, conversation.id);
    addToColumn(sourceLabel, {
      ...conversation,
      labels: oldLabels,
    });

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

onMounted(fetchBoard);
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
          class="h-9 px-4 rounded-lg text-sm font-medium text-white bg-n-brand hover:bg-n-brand/90"
          :disabled="isLoading"
          @click="fetchBoard"
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
        v-else-if="!visibleLabels.length"
        class="flex items-center justify-center h-full px-8"
      >
        <div class="max-w-md text-center">
          <h2 class="m-0 text-base font-semibold text-n-slate-12">
            No hay etiquetas visibles
          </h2>
          <p class="mt-2 mb-0 text-sm text-n-slate-11">
            Crea etiquetas o actívalas para mostrarlas en la barra lateral.
          </p>
        </div>
      </div>

      <div
        v-else
        class="flex h-full gap-4 px-8 py-6 overflow-x-auto overflow-y-hidden"
      >
        <section
          v-for="label in visibleLabels"
          :key="label.id"
          class="flex flex-col flex-shrink-0 w-[320px] max-h-full rounded-xl border border-n-weak bg-n-alpha-1"
          @dragover.prevent
          @drop="onDrop(label)"
        >
          <header class="flex items-center justify-between gap-3 px-4 py-3 border-b border-n-weak">
            <div class="flex items-center min-w-0 gap-2">
              <span
                class="flex-shrink-0 size-2.5 rounded-sm"
                :style="{ backgroundColor: label.color }"
              />
              <h2 class="m-0 text-sm font-semibold truncate text-n-slate-12">
                {{ label.title }}
              </h2>
            </div>

            <span class="px-2 py-0.5 rounded-md text-xs font-medium text-n-slate-11 bg-n-alpha-2">
              {{ conversationsByLabel[label.title]?.length || 0 }}
            </span>
          </header>

          <div class="flex-1 p-3 overflow-y-auto">
            <article
              v-for="conversation in conversationsByLabel[label.title] || []"
              :key="conversation.id"
              draggable="true"
              class="p-3 mb-3 transition-colors border rounded-lg cursor-grab border-n-weak bg-n-solid-1 hover:bg-n-alpha-2 active:cursor-grabbing"
              :class="{
                'opacity-50 pointer-events-none': movingConversationId === conversation.id,
              }"
              @dragstart="onDragStart(conversation, label.title)"
              @dragend="onDragEnd"
              @click="openConversation(conversation)"
            >
              <div class="flex items-start justify-between gap-2">
                <h3 class="m-0 text-sm font-semibold leading-5 text-n-slate-12 line-clamp-2">
                  {{ getConversationTitle(conversation) }}
                </h3>

                <span class="flex-shrink-0 text-xs text-n-slate-10">
                  #{{ conversation.id }}
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
            </article>

            <div
              v-if="!(conversationsByLabel[label.title] || []).length"
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
