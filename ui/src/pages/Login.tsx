import { useState } from 'react'
import { Button, Card, Form, Input, message } from 'antd'
import axios from 'axios'
import { useNavigate } from 'react-router-dom'

export default function Login() {
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()
  const onFinish = async (values: any) => {
    setLoading(true)
    try {
      const { data } = await axios.post('/api/auth/login', values)
      localStorage.setItem('token', data.token)
      axios.defaults.headers.common['Authorization'] = `Bearer ${data.token}`
      message.success('Connecté')
      navigate('/', { replace: true })
    } catch {
      message.error('Identifiants invalides')
    } finally {
      setLoading(false)
    }
  }
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' }}>
      <Card title="Connexion" style={{ width: 360 }}>
        <Form layout="vertical" onFinish={onFinish}>
          <Form.Item name="username" label="Utilisateur" rules={[{ required: true }]}>
            <Input autoFocus />
          </Form.Item>
          <Form.Item name="password" label="Mot de passe" rules={[{ required: true }]}>
            <Input.Password />
          </Form.Item>
          <Button type="primary" htmlType="submit" loading={loading} block>Se connecter</Button>
        </Form>
      </Card>
    </div>
  )
}
