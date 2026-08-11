import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';

const meta = {
  permissions: ['administrator', 'supervisor'],
};

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/agent-access'),
      component: SettingsWrapper,
      meta,
      children: [
        {
          path: '',
          name: 'agent_access_settings_index',
          component: Index,
          meta,
        },
      ],
    },
  ],
};
