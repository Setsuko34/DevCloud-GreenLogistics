import { startConsumer } from './consumer'
import pino from 'pino'

const logger = pino()

startConsumer()
  .then(() => logger.info('Notification consumer started'))
  .catch((err) => { logger.error(err); process.exit(1) })
