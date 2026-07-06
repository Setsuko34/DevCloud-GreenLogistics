import { FastifyInstance } from 'fastify'

const DEFAULT_ALLOWED_ORIGINS = 'http://app.greenlogistics.local,http://localhost:5173'

export async function wsRoutes(app: FastifyInstance) {
  const allowedOrigins = (process.env.ALLOWED_ORIGINS || DEFAULT_ALLOWED_ORIGINS).split(',')

  app.get('/positions', { websocket: true }, (socket, req) => {
    if (!allowedOrigins.includes(req.headers.origin ?? '')) {
      socket.close(1008, 'forbidden origin')
      return
    }
    app.positionClients.add(socket)
    socket.on('close', () => app.positionClients.delete(socket))
  })
}
