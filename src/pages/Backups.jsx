import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { backupsAPI, restoreAPI } from '../services/api'
import { useApp } from '../context/AppContext'
import styles from './Backups.module.css'
import { useSelector } from 'react-redux'
import { userRoles } from '../services/role'

const Backups = () => {
  const navigate = useNavigate()
  // const { backups: contextBackups, refreshBackups } = useApp()
  const [backups, setBackups] = useState()
  const [loading, setLoading] = useState(true)
  const [triggering, setTriggering] = useState({})

  const { role, userid } = useSelector((state) => state.user)

  // useEffect(() => {
  //   if (contextBackups.length > 0) {
  //     setBackups(contextBackups)
  //     setLoading(false)
  //   } else {
  //     loadBackups()
  //   }
  // }, [contextBackups])

  // useEffect(() => {
  //   loadBackups()
  // }, [])

  const loadBackups = async () => {

    try {

      setLoading(true)
      // setBackups([])

      if (role == userRoles.level2) {
        const data = await backupsAPI.list()
        //console.log(data)
        setBackups(data)
      }

      if (role == userRoles.level1) {

        const admindata = await backupsAPI.list()
        const userdata = await restoreAPI.getUserHosts({ userid })
        const matchedObjects = admindata?.filter(host_name =>
          userdata?.hosts?.includes(host_name.hostname)
        );
        setBackups(matchedObjects)

      }
    } catch (error) {
      console.error('Error loading backups:', error)
      alert('Failed to load backups')
    } finally {
      setLoading(false)
    }
  }


  useEffect(() => {

    loadBackups()
    let timer = setInterval(() => {

      loadBackups()
    }, 15000)


    return () => {
      clearInterval(timer)
    }

  }, [])



  const triggerBackup = async (hostname, type) => {
    try {
      setTriggering(prev => ({ ...prev, [`${hostname}_${type}`]: true }))
      const result = await backupsAPI.trigger(hostname, type)
      alert(result.message || `${type} backup started for ${hostname}`)
      refreshBackups()
      loadBackups()
    } catch (error) {
      // console.error('Error triggering backup:', error)
      //alert('Failed to trigger backup')
    } finally {
      setTriggering(prev => ({ ...prev, [`${hostname}_${type}`]: false }))
    }
  }

  const getStatusColor = (status) => {
    switch (status.toLowerCase()) {
      case 'success':
        return '#28a745'
      case 'failed':
        return '#dc3545'
      case 'running':
        return '#ffc107'
      default:
        return '#6c757d'
    }
  }

  if (loading) {
    return <div className={styles.container}>Loading...</div>
  }

  return (
    <div className={styles.container}>
      
      <div className={styles.buttonBar}>
        <h1>Backup Management</h1>

        <button
          onClick={() => navigate("/")}
          className={styles.backButton}
        >
          ← Back to Home
        </button>
      </div>

      <table className={styles.table}>
        <thead>
          <tr>
            <th>Hostname</th>
            <th>Last Backup</th>
            <th>Status</th>
            <th>Actions</th>
          </tr>
        </thead>
        <tbody>
          {backups?.length === 0 ? (
            <tr>
              <td colSpan="4" style={{ textAlign: 'center' }}>
                No backups found.
              </td>
            </tr>
          ) : (
            backups?.map(backup => (
              <tr key={backup.hostname}>
                <td>{backup.hostname}</td>
                <td>{backup.lastBackup}</td>
                <td>
                  <span
                    style={{
                      color: getStatusColor(backup.status),
                      fontWeight: 'bold'
                    }}
                  >
                    {backup.status}
                  </span>
                </td>
                <td>
                  <button
                    type="button"   // ✅ ADD THIS
                    className={styles.backupButton}
                    onClick={() => {
                      console.log("Button clicked");
                      if (window.confirm("The Backup will start immediately. Please confirm.")) {
                        triggerBackup(backup.hostname, 'full');
                      }
                    }}
                    disabled={triggering[`${backup.hostname}_full`]}
                  >
                    {triggering[`${backup.hostname}_full`] ? 'Starting...' : 'Full Backup'}
                  </button>

                  <button
                    type="button"   // ✅ ADD THIS
                    className={styles.backupButton}
                    onClick={() => {
                      console.log("Button clicked");
                      if (window.confirm("The Backup will start immediately. Please confirm.")) {
                        triggerBackup(backup.hostname, 'incremental');
                      }
                    }}
                    disabled={triggering[`${backup.hostname}_incremental`]}
                  >
                    {triggering[`${backup.hostname}_incremental`] ? 'Starting...' : 'Incremental Backup'}
                  </button>
                </td>

              </tr>
            ))
          )}
        </tbody>
      </table>

      <button onClick={() => navigate('/')} className={styles.backButton}>
        ← Back to Home
      </button>
    </div>
  )
}

export default Backups

