import nodemailer from 'nodemailer'

interface ParcelEvent {
  parcel_id: string
  event: string
  recipient_email: string
}

export function buildMailOptions(event: ParcelEvent) {
  return {
    from: process.env.NOTIFICATION_FROM || 'alerts@greenlogistics.local',
    to: event.recipient_email,
    subject: `GreenLogistics — Votre colis arrive dans 5 min !`,
    text: `Bonjour,\n\nVotre colis ${event.parcel_id} sera livré dans environ 5 minutes.\n\nBonne journée,\nL'équipe GreenLogistics`
  }
}

export function createTransport() {
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST || 'localhost',
    port: Number(process.env.SMTP_PORT) || 1025,
    secure: false
  })
}
