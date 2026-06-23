import { BrowserRouter, Routes, Route, Link } from 'react-router-dom'
import { TrackingPage } from './pages/TrackingPage'
import { DashboardPage } from './pages/DashboardPage'

export default function App() {
  return (
    <BrowserRouter>
      <nav style={{ padding: '1rem', borderBottom: '1px solid #eee' }}>
        <Link to="/" style={{ marginRight: '1rem' }}>Suivi colis</Link>
        <Link to="/dashboard">Dashboard démo</Link>
      </nav>
      <Routes>
        <Route path="/" element={<TrackingPage />} />
        <Route path="/dashboard" element={<DashboardPage />} />
      </Routes>
    </BrowserRouter>
  )
}
