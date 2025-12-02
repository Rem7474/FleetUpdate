import { useEffect, useState } from 'react'
import { useParams } from 'react-router-dom'
import axios from 'axios'
import { Alert, Button, Card, Descriptions, Empty, Typography } from 'antd'
import { useRef } from 'react'

type AgentDetail = { id: string; status: string; last_seen: string; apps_state?: Record<string, any> }

export default function VmDetail() {
  const { id } = useParams()
  const [agent, setAgent] = useState<AgentDetail | null>(null)
  const [log, setLog] = useState('')
  const esRef = useRef<EventSource | null>(null)
  useEffect(() => {
    if (!id) return
    axios.get(`/api/agents/${id}`).then(r => setAgent(r.data))
  }, [id])
  const startUpgrade = async () => {
    if (!id) return
    const body = {
      command: 'apt_upgrade',
      commands: [],
    }
    const { data } = await axios.post(`/api/agents/${id}/commands`, body)
    const cmdId: string = data.command_id
    if (esRef.current) { esRef.current.close(); esRef.current = null }
    setLog('')
    const token = localStorage.getItem('token') || ''
    const es = new EventSource(`/api/commands/${cmdId}/stream?token=${encodeURIComponent(token)}`)
    es.onmessage = (e) => setLog(prev => prev + e.data + '\n')
    es.onerror = () => es.close()
    esRef.current = es
  }
  if (!agent) return <Empty description="No data" />
  const osUpdate: any = (agent as any).os_update || null
  const sudoOk = osUpdate?.sudo_apt_ok !== false
  return (
    <Card title={`VM ${agent.id}`}>
      <Descriptions bordered column={1} items={[
        { key: 'status', label: 'Status', children: agent.status },
        { key: 'last_seen', label: 'Last seen', children: new Date(agent.last_seen).toLocaleString() },
        { key: 'os_update', label: 'OS updates', children: osUpdate ? (
          <span>
            {osUpdate.status} ({osUpdate.upgrades ?? 0} upgradable)
          </span>
        ) : 'n/a' },
      ]} />
      {!sudoOk && (
        <Alert
          style={{ marginTop: 16 }}
          type="warning"
          message="Sudoers non configuré pour apt"
          description={
            <span>
              Cette action nécessite que l'utilisateur de l'agent puisse exécuter <code>apt</code> sans mot de passe (NOPASSWD).
              Ajoutez une entrée sudoers, par exemple: <code>orchestrator ALL=(root) NOPASSWD:/usr/bin/apt</code>.
            </span>
          }
          showIcon
        />
      )}
      <Card title="Apps" style={{ marginTop: 16 }}>
        <pre style={{ margin: 0 }}>{JSON.stringify(agent.apps_state ?? {}, null, 2)}</pre>
      </Card>
      <Card
        title="Upgrade OS"
        style={{ marginTop: 16 }}
        extra={<Button type="primary" onClick={startUpgrade} disabled={!sudoOk}>Run apt upgrade</Button>}
      >
        <Typography.Paragraph type="secondary" style={{ marginBottom: 8 }}>
          Nécessite sudoers NOPASSWD pour <code>apt update</code> et <code>apt upgrade</code>.
        </Typography.Paragraph>
        <pre style={{ margin: 0, maxHeight: 300, overflow: 'auto', background: '#111', color: '#0f0', padding: 12 }}>{log}</pre>
      </Card>
    </Card>
  )
}
