import { useEffect, useState } from 'react'
import axios from 'axios'
import { Badge, Button, Card, Input, List, Segmented, Space, Tag, Typography, message } from 'antd'
import { Link } from 'react-router-dom'
import { useNavigate } from 'react-router-dom'
import axios from 'axios'

type Agent = { id: string; status: string; last_seen: string; os_update?: any; uptime_seconds?: number; outdated?: boolean }

export default function Dashboard() {
  const [agents, setAgents] = useState<Agent[]>([])
  const [loading, setLoading] = useState(false)
  const navigate = useNavigate()
  const [filter, setFilter] = useState<'all'|'outdated'>('all')
  const [q, setQ] = useState('')
  useEffect(() => {
    setLoading(true)
    axios.get('/api/agents')
      .then(r => setAgents(r.data))
      .catch(err => {
        if (err?.response?.status === 401) navigate('/login')
      })
      .finally(() => setLoading(false))
  }, [])

  // Live updates via WebSocket
  useEffect(() => {
    const token = localStorage.getItem('token') || ''
    const ws = new WebSocket(`${location.protocol === 'https:' ? 'wss' : 'ws'}://${location.host}/api/ws?token=${encodeURIComponent(token)}`)
    ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(e.data)
        if (msg.type === 'agent_update') {
          setAgents(prev => {
            const copy = [...prev]
            const idx = copy.findIndex(a => a.id === msg.agent.id)
            const updated = {
              id: msg.agent.id,
              status: msg.agent.status,
              last_seen: msg.agent.last_seen,
              os_update: msg.agent.os_update,
            }
            if (idx >= 0) copy[idx] = { ...copy[idx], ...updated }
            else copy.unshift(updated as Agent)
            return copy
          })
        }
      } catch {}
    }
    ws.onerror = () => {
      // silent; falls back to manual refresh
    }
    return () => ws.close()
  }, [])

  const filtered = agents
    .filter(a => filter === 'all' ? true : !!a.outdated || (a.os_update?.upgrades ?? 0) > 0)
    .filter(a => a.id.toLowerCase().includes(q.toLowerCase()))

  const runUpgrade = async (agentId: string) => {
    try {
      const { data } = await axios.post(`/api/agents/${agentId}/commands`, { command: 'apt_upgrade', commands: [] })
      message.success(`Upgrade lancé (${data.command_id})`)
    } catch {
      message.error('Echec lancement upgrade')
    }
  }

  const sudoCheck = async (agentId: string) => {
    try {
      await axios.post(`/api/agents/${agentId}/sudo-check`)
      message.success('Sudo check lancé')
    } catch {
      message.error('Echec sudo check')
    }
  }
  return (
    <Card title="Agents" loading={loading}
      extra={
        <Space>
          <Segmented options={[{label:'Tous', value:'all'},{label:'Obsolètes', value:'outdated'}]} value={filter} onChange={(v)=>setFilter(v as any)} />
          <Input placeholder="Recherche..." value={q} onChange={e=>setQ(e.target.value)} allowClear />
        </Space>
      }
    >
      <List
        dataSource={filtered}
        renderItem={(a) => (
          <List.Item actions={[
            <Button key="sudo" onClick={()=>sudoCheck(a.id)}>Sudo check</Button>,
            <Button key="up" type="primary" onClick={()=>runUpgrade(a.id)} disabled={a.os_update?.sudo_apt_ok === false}>Upgrade</Button>,
          ]}>
            <List.Item.Meta
              title={<Link to={`/vm/${a.id}`}>{a.id}</Link>}
              description={<Typography.Text type="secondary">Dernière vue: {new Date(a.last_seen).toLocaleString()}</Typography.Text>}
            />
            <Space>
              <Tag color={a.status === 'online' ? 'green' : 'default'}>{a.status}</Tag>
              {a.os_update && (
                <Badge status={(a.os_update.upgrades ?? 0) > 0 ? 'error' : 'success'} text={`MAJ: ${a.os_update.upgrades ?? 0}`} />
              )}
              {a.os_update && a.os_update.sudo_apt_ok === false && (
                <Tag color="orange">sudo non configuré</Tag>
              )}
            </Space>
          </List.Item>
        )}
      />
    </Card>
  )
}
