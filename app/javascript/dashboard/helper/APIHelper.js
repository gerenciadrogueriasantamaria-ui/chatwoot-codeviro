import Cookies from 'js-cookie';
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

const AGENT_ACCESS_ERROR_CODES = [
  'outside_schedule',
  'max_sessions_reached',
  'session_revoked',
  'access_denied',
];

const AGENT_ACCESS_ERROR_CODES = [
    const clearAgentAccessBrowserSession = () => {
  Cookies.remove('cw_d_session_info');
  Cookies.remove('auth_data');
  Cookies.remove('user');
  window.localStorage.removeItem(AGENT_ACCESS_CLIENT_ID_KEY);
};
const parseErrorCode = error => {
  const errorCode = error?.response?.data?.error_code;

  if (
    error?.response?.status === 401 &&
    AGENT_ACCESS_ERROR_CODES.includes(errorCode)
  ) {
    clearAgentAccessBrowserSession();

if (window.location.pathname !== '/app/login') {
  window.location.replace('/app/login');
}

return Promise.reject(error);
  }

  return Promise.reject(error);
};

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
