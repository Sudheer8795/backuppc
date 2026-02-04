// import { useState, useEffect } from 'react'
// import { useNavigate } from 'react-router-dom'
// import { globalConfigAPI } from '../services/api'
// import styles from './GlobalConfig.module.css'

// const GlobalConfig = () => {
//   const navigate = useNavigate()
//   const [loading, setLoading] = useState(true)
//   const [saving, setSaving] = useState(false)
//   const [formData, setFormData] = useState({
//     topDir: '',
//     maxBackups: 5,
//     compressLevel: 6,
//     fillCycle: 10
//   })

//   useEffect(() => {
//     loadConfig()
//   }, [])

//   const loadConfig = async () => {
//     try {
//       setLoading(true)
//       const config = await globalConfigAPI.get()
//       setFormData(config)
//     } catch (error) {
//       console.error('Error loading config:', error)
//       alert('Failed to load configuration')
//     } finally {
//       setLoading(false)
//     }
//   }

//   const handleChange = (e) => {
//     const { name, value } = e.target
//     setFormData(prev => ({
//       ...prev,
//       [name]: name === 'topDir' ? value : Number(value) || value
//     }))
//   }

//   const handleSubmit = async (e) => {
//     e.preventDefault()
//     try {
//       setSaving(true)
//       await globalConfigAPI.save(formData)
//       alert('Global configuration saved successfully!')
//     } catch (error) {
//       console.error('Error saving config:', error)
//       alert('Failed to save configuration')
//     } finally {
//       setSaving(false)
//     }
//   }

//   if (loading) {
//     return <div className={styles.container}>Loading...</div>
//   }

//   return (
//     <div className={styles.container}>
//       <h1>Global Configuration</h1>
//       <form onSubmit={handleSubmit} className={styles.form}>
//         <label htmlFor="topDir">Data Directory (Backup Store Root):</label>
//         <input
//           type="text"
//           id="topDir"
//           name="topDir"
//           value={formData.topDir}
//           onChange={handleChange}
//           placeholder="/var/lib/backuppc/data"
//           required
//         />

//         <label htmlFor="maxBackups">Max Full Backups to Keep:</label>
//         <input
//           type="number"
//           id="maxBackups"
//           name="maxBackups"
//           value={formData.maxBackups}
//           onChange={handleChange}
//           min="1"
//           max="100"
//           required
//         />

//         <label htmlFor="compressLevel">Compression Level (0-9):</label>
//         <input
//           type="number"
//           id="compressLevel"
//           name="compressLevel"
//           value={formData.compressLevel}
//           onChange={handleChange}
//           min="0"
//           max="9"
//           required
//         />

//         <label htmlFor="fillCycle">Fill Cycle (Days):</label>
//         <input
//           type="number"
//           id="fillCycle"
//           name="fillCycle"
//           value={formData.fillCycle}
//           onChange={handleChange}
//           min="0"
//           max="30"
//           required
//         />

//         <button type="submit" disabled={saving}>
//           {saving ? 'Saving...' : 'Save Global Configuration'}
//         </button>
//       </form>

//       <button onClick={() => navigate('/')} className={styles.backButton}>
//         ← Back to Home
//       </button>
//     </div>
//   )
// }

// export default GlobalConfig

import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { globalConfigAPI } from '../services/api'
import styles from './GlobalConfig.module.css'

const GlobalConfig = () => {
  const navigate = useNavigate()
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)

  const [formData, setFormData] = useState({
    backupStoreIp: '',
    backupShare: '',
    backupUser: '',
    backupPassword: '',
    maxBackups: 7,
    compressLevel: 6,
    fillCycle: 10
  })

  // 🔹 TEMP: No GET config yet
  useEffect(() => {
    setLoading(false)
  }, [])

  const handleChange = (e) => {
    const { name, value } = e.target
    setFormData(prev => ({
      ...prev,
      [name]: ['maxBackups', 'compressLevel', 'fillCycle'].includes(name)
        ? Number(value)
        : value
    }))
  }

  const handleSubmit = async (e) => {
    e.preventDefault()
    try {
      setSaving(true)
      await globalConfigAPI.save(formData)
      alert('Global configuration saved successfully!')
    } catch (error) {
      console.error('Error saving config:', error)
      alert('Failed to save configuration')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return <div className={styles.container}>Loading...</div>
  }

  return (
    <div className={styles.container}>
      <h1>Global Configuration</h1>

      <form onSubmit={handleSubmit} className={styles.form}>

        {/* 🔹 SAMBA BACKUP STORE CONFIG */}
        <h3>Backup Storage (Samba)</h3>

        <label>Backup Store IP</label>
        <input
          type="text"
          name="backupStoreIp"
          value={formData.backupStoreIp}
          onChange={handleChange}
          placeholder="192.168.1.63"
          required
        />

        <label>Share Name</label>
        <input
          type="text"
          name="backupShare"
          value={formData.backupShare}
          onChange={handleChange}
          placeholder="SharedFolder"
          required
        />

        <label>Username</label>
        <input
          type="text"
          name="backupUser"
          value={formData.backupUser}
          onChange={handleChange}
          required
        />

        <label>Password</label>
        <input
          type="password"
          name="backupPassword"
          value={formData.backupPassword}
          onChange={handleChange}
          required
        />

        {/* 🔹 BACKUP POLICY */}
        <h3>Backup Policy</h3>

        <label>Max Full Backups to Keep</label>
        <input
          type="number"
          name="maxBackups"
          value={formData.maxBackups}
          onChange={handleChange}
          min="1"
          max="100"
          required
        />

        <label>Compression Level (0–9)</label>
        <input
          type="number"
          name="compressLevel"
          value={formData.compressLevel}
          onChange={handleChange}
          min="0"
          max="9"
          required
        />

        <label>Fill Cycle (Days)</label>
        <input
          type="number"
          name="fillCycle"
          value={formData.fillCycle}
          onChange={handleChange}
          min="0"
          max="30"
          required
        />

        <button type="submit" disabled={saving}>
          {saving ? 'Saving...' : 'Save Global Configuration'}
        </button>
      </form>

      <button onClick={() => navigate('/')} className={styles.backButton}>
        ← Back to Home
      </button>
    </div>
  )
}

export default GlobalConfig
