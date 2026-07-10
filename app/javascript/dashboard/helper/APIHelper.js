import Auth from '../api/auth';

const AGENT_ACCESS_CLIENT_ID_KEY = 'cw_agent_access_client_id';

const getAgentAccessClientId = () => {
  let clientId = window.localStorage.getItem(AGENT_ACCESS_CLIENT_ID_KEY);

  if (!clientId) {
    clientId = window.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`;
    window.localStorage.setItem(AGENT_ACCESS_CLIENT_ID_KEY, clientId);
  }

  return clientId;
};

const parseErrorCode = error => Promise.reject(error);

export default axios => {
  const { apiHost = '' } = window.chatwootConfig || {};
  const wootApi = axios.create({ baseURL: `${apiHost}/` });

  // Add Auth Headers to requests if logged in
  if (Auth.hasAuthCookie()) {
    const {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    } = Auth.getAuthData();

    Object.assign(wootApi.defaults.headers.common, {
      'access-token': accessToken,
      'token-type': tokenType,
      client,
      expiry,
      uid,
    });
  }

  wootApi.interceptors.request.use(config => {
    config.headers['X-Agent-Access-Client-Id'] = getAgentAccessClientId();
    return config;
  });

  // Response parsing interceptor
  wootApi.interceptors.response.use(
    response => response,
    error => parseErrorCode(error)
  );

  return wootApi;
};
