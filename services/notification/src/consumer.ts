import { Kafka } from 'kafkajs'
import pino from 'pino'
import { buildMailOptions, createTransport } from './mailer'

const logger = pino()

export async function startConsumer() {
  const kafka = new Kafka({
    clientId: 'notification-service',
    brokers: (process.env.REDPANDA_BROKERS || 'localhost:9092').split(',')
  })

  const consumer = kafka.consumer({ groupId: 'notification-group' })
  const transport = createTransport()
  const notified = new Set<string>()

  await consumer.connect()
  await consumer.subscribe({ topic: 'parcels.events', fromBeginning: false })

  await consumer.run({
    eachMessage: async ({ message }) => {
      if (!message.value) return
      const event = JSON.parse(message.value.toString())

      if (event.event !== 'near_5min') return
      if (notified.has(event.parcel_id)) {
        logger.info({ parcel_id: event.parcel_id }, 'Already notified, skipping')
        return
      }

      try {
        await transport.sendMail(buildMailOptions(event))
        notified.add(event.parcel_id)
        logger.info({ parcel_id: event.parcel_id, to: event.recipient_email }, 'Notification sent')
      } catch (err) {
        logger.error({ err, parcel_id: event.parcel_id }, 'Failed to send notification')
      }
    }
  })
}
