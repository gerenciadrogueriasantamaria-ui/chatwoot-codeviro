import axios from 'axios';

const AGENT_ACCESS_CLIENT_ID_KEY = 'cw_agent_access_client_id';

const getAgentAccessClientId = () => {
  let clientId = window.localStorage.getItem(AGENT_ACCESS_CLIENT_ID_KEY);

  if (!clientId) {
    clientId = window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`;
    window.localStorage.setItem(AGENT_ACCESS_CLIENT_ID_KEY, clientId);
  }

  return clientId;
};

const { apiHost = '' } = window.chatwootConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

wootAPI.interceptors.request.use(config => {
  config.headers['X-Agent-Access-Client-Id'] = getAgentAccessClientId();
  return config;
});

export default wootAPI;
