import { publishAgentV2Update } from '../../../util/agentV2Updates';
import { addActionHandler } from '../../index';

addActionHandler('apiUpdate', (global, actions, update) => {
  if (update.type === 'agentV2') publishAgentV2Update(update.update);
});
