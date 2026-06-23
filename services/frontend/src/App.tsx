import { BrowserRouter, Routes, Route, Link, NavLink } from 'react-router-dom'
import { TrackingPage } from './pages/TrackingPage'
import { DashboardPage } from './pages/DashboardPage'

export default function App() {
  return (
    <BrowserRouter>
      <nav>
        <span className="nav-brand">🌿 GreenLogistics</span>
        <NavLink to="/">Suivi colis</NavLink>
        <NavLink to="/dashboard">Dashboard</NavLink>
      </nav>
      <Routes>
        <Route path="/" element={<TrackingPage />} />
        <Route path="/dashboard" element={<DashboardPage />} />
      </Routes>
    </BrowserRouter>
  )
}
