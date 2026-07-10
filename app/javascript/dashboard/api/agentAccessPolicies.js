import ApiClient from './ApiClient';

class AgentAccessPoliciesAPI extends ApiClient {
  constructor() {
    super('agent_access_policies', { accountScoped: true });
  }

  getUsers() {
    return this.get();
  }

  getPolicy(userId) {
    return this.show(userId);
  }

  updatePolicy(userId, data) {
    return this.update(userId, data);
  }

  deleteSession(userId, sessionId) {
    return axios.delete(`${this.url}/${userId}/sessions/${sessionId}`);
  }
}

export default new AgentAccessPoliciesAPI();
