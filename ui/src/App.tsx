import { Layout, Menu, Typography } from 'antd'
import { Link, Outlet, useLocation } from 'react-router-dom'

const { Header, Content } = Layout

export default function App() {
  const loc = useLocation()
  const key = loc.pathname.startsWith('/logs') ? 'logs' : loc.pathname.startsWith('/vm/') ? 'vms' : 'home'
  const token = typeof window !== 'undefined' ? localStorage.getItem('token') : null
  const menuItems = [
    { key: 'home', label: <Link to="/">Dashboard</Link> },
    { key: 'vms', label: <Link to="/">VMs</Link> },
    { key: 'logs', label: <Link to="/logs">Logs</Link> },
    token ? { key: 'logout', label: <a onClick={() => { localStorage.removeItem('token'); location.href = '/login' }}>Logout</a> } : { key: 'login', label: <Link to="/login">Login</Link> },
  ]
  return (
    <Layout style={{ minHeight: '100vh' }}>
      <Header style={{ display: 'flex', alignItems: 'center' }}>
        <Typography.Title level={4} style={{ color: '#fff', margin: 0, marginRight: 24 }}>FleetUpdate</Typography.Title>
        <Menu theme="dark" mode="horizontal" selectedKeys={[key]} items={menuItems} />
      </Header>
      <Content style={{ padding: 24 }}>
        <Outlet />
      </Content>
    </Layout>
  )
}
