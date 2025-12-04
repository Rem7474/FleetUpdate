import React from 'react'
import ReactDOM from 'react-dom/client'
import { createBrowserRouter, RouterProvider, Navigate } from 'react-router-dom'
import App from './App'
import Dashboard from './pages/Dashboard'
import VmDetail from './pages/VmDetail'
import Logs from './pages/Logs'
import Login from './pages/Login'
import axios from 'axios'

const token = localStorage.getItem('token')
if (token) {
  axios.defaults.headers.common['Authorization'] = `Bearer ${token}`
}

function RequireAuth({ children }: { children: React.ReactElement }) {
  const hasToken = !!localStorage.getItem('token')
  return hasToken ? children : <Navigate to="/login" replace />
}

const router = createBrowserRouter([
  {
    path: '/',
    element: (
      <RequireAuth>
        <App />
      </RequireAuth>
    ),
    children: [
      { index: true, element: <Dashboard /> },
      { path: 'vm/:id', element: <VmDetail /> },
      { path: 'logs', element: <Logs /> },
    ],
  },
  { path: '/login', element: <Login /> },
])

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <RouterProvider router={router} />
  </React.StrictMode>,
)
