import { useEffect, useState } from "react";
import { getProviders, saveProvider, updateProvider, getSchedularDetails, saveSchedule, getTransferPolicies, saveTransferPolicies, deleteProvider } from '../services/api';
import layoutStyles from "../components/Layout.module.css";


const card = {
  padding: '14px 16px',
  borderRadius: '12px',
  background: '#fff',
  boxShadow: '0 8px 20px rgba(17, 24, 39, 0.06)',
  border: '1px solid #e5e7eb'
}
const th = {
  textAlign: "left",
  padding: "8px",
  borderBottom: "1px solid #e5e7eb",
  color: "#6b7280",
  fontWeight: 600,
};

const td = {
  padding: "8px",
  borderBottom: "1px solid #e5e7eb",
};

const inputStyle = {
  width: '100%',
  padding: '6px 8px',
  fontSize: 14,
  border: '1px solid #ccc',
  borderRadius: 4,
  outline: 'none',
  boxSizing: 'border-box'
};
const iconBtnStyle = {
  padding: "4px",
  borderRadius: 6,
  border: "1px solid #d1d5db",
  background: "#f9fafb",
  cursor: "pointer",
};



const label = { display: 'flex', flexDirection: 'column', gap: 4, fontSize: 13, color: '#374151' }
const input = { padding: '8px 10px', borderRadius: 8, border: '1px solid #d1d5db', fontSize: 14 }
const select = input
const hint = { fontSize: 12, color: '#6b7280' }

const hosts = [
  { host: 'farside', schedule: 'inherit', cron: '0 2 * * *', window: '02:00-04:00' },
  { host: 'larson', schedule: 'custom', cron: '30 3 * * 1-6', window: '03:00-05:00' },
  { host: 'apollo', schedule: 'inherit', cron: '0 2 * * *', window: '02:00-04:00' },
  { host: 'zeus', schedule: 'custom', cron: '15 1 * * 0', window: '01:00-03:00' }
]

const providerAssignments = [
  { host: 'farside', provider: 'AWS S3', secondary: 'GCS', mode: 'inherit' },
  { host: 'larson', provider: 'Azure Blob', secondary: '—', mode: 'custom' },
  { host: 'apollo', provider: 'AWS S3', secondary: '—', mode: 'inherit' },
  { host: 'zeus', provider: 'GCS', secondary: 'AWS S3', mode: 'custom' }
]

const providersList = [
  { name: 'AWS S3', type: 'S3', bucket: 'backuppc-prod', region: 'us-east-1', status: 'Healthy' },
  { name: 'Azure Blob', type: 'Azure', bucket: 'backuppc-az', region: 'eastus', status: 'Healthy' },
  { name: 'GCS', type: 'GCS', bucket: 'backuppc-gcs', region: 'us-central1', status: 'Standby' }
]

const CloudSettings = () => {
  const [providersList, setProvidersList] = useState([]);
  const [schedule, setSchedule] = useState([]);

  const [form, setForm] = useState({
    providerType: "",
    instanceName: "",
    region: "",
    accessKey: "",
    secretKey: ""
  });
  const [data, setData] = useState({
    mode: "After every backup",
    bandwidth: "",
    retries: "",
    parallel: ""
  });

  const [isEdit, setIsEdit] = useState(false);
  const [editingProvider, setEditingProvider] = useState(null);
  const [saving, setSaving] = useState(false);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    loadProviders();
    getScheduleDetails();
  }, []);
  /* LOAD from backend */
  useEffect(() => {
    getTransferPolicies()
      .then(res => {
        if (res && Object.keys(res).length) {
          setData(res);
        }
      })
      .catch(err => {
        console.error("Failed to load transfer policies", err);
      });
  }, []);

  /* SAVE to backend */
  const savePolicies = async () => {
    try {
      setSaving(true);
      await saveTransferPolicies(data);
      alert("Transfer policies saved successfully");
    } catch (err) {
      console.error(err);
      alert("Failed to save transfer policies");
    } finally {
      setSaving(false);
    }
  };


  const updateRow = (e) => {
    // setSchedule(prev => {
    //   const copy = [...prev];
    //   copy[index] = { ...copy[index], [field]: value };
    //   return copy;
    // });

    const { name, value } = e.target;

    // Set new state object with updated key or new key
    setSchedule((prevState) => ({
      ...prevState,
      [name]: value
    }));
  };

  const handleSaveSchedule = async () => {

    const res = await saveSchedule(schedule);
     
    try{
        alert('Schedule saved successfully');
        getScheduleDetails();
    }
    catch(err){
      alert('Save failed');
    }
      
  };

  const getScheduleDetails = async () => {
    try {
      const data = await getSchedularDetails();   // already JSON

      setSchedule(data);

      // console.log(data);
    } catch (err) {
      console.error(err);
      alert("Failed to get scheduler details");
    }
  };

  const PROVIDER_TYPE_MAP = {
    s3: "AWS_S3",
    aws_s3: "AWS_S3",

    azureblob: "AZURE_BLOB",
    azure_blob: "AZURE_BLOB",

    gcs: "GCS",

    drive: "GDRIVE",
    gdrive: "GDRIVE",

    s3compat: "S3_COMPAT",
    s3_compatible: "S3_COMPAT",
  };

  function handleEdit(p) {
    let providerValue = '';
    switch (p.provider.toLowerCase()) {
      case 'aws s3':
      case 's3':
        providerValue = 's3';
        break;
      case 'azure blob':
      case 'azureblob':
        providerValue = 'azureblob';
        break;
      case 'gdrive':
      case 'drive':
      case 'google drive':
        providerValue = 'drive';
        break;
      default:
        providerValue = '';
    }
    setForm({
      provider: providerValue,
      instanceName: p.name,
      region: p.region || "",
      accessKey: "",
      secretKey: ""
    });
    setEditingProvider(p.name);
    setIsEdit(true);
  }

  useEffect(() => {
    loadProviders();
  }, []);

  function resetForm() {
    setForm({
      provider: "",
      instanceName: "",
      region: "",
      accessKey: "",
      secretKey: ""
    });
    setIsEdit(false);
    setEditingProvider(null);
  }

  async function loadProviders() {
    try {
      setLoading(true);
      const data = await getProviders();
      setProvidersList(data);
    } catch (err) {
      console.error(err);
    }
    finally {
      setLoading(false);             // stop loader
    }

  }
  const handleClear = async () => {
    // await loadProviders(); // reload table data

    setForm({
      provider: "Select Provider",
      bucketName: "",
      region: "",
      accessKey: "",
      secretKey: "",
    });

    setEditingProvider(null); // remove row highlight
    setIsEdit(false);
  };

  async function handleSave() {
    try {
      await saveProvider(form);
      alert("Provider saved successfully");
      resetForm();
      loadProviders();
    } catch (e) {
      alert(e.message);
    }
  }

  async function handleUpdate() {
    try {
      await updateProvider(editingProvider, form);
      alert("Provider updated successfully");
      setIsEdit(false);
      resetForm();
      loadProviders();
    } catch (e) {
      alert(e.message);
    }
  }

  async function handleDelete(p) {
    try {
      await deleteProvider(p);
      alert("Provider deleted");
      loadProviders();
    } catch (e) {
      alert(e.message);
    }
  }
  return (
    <div>
      <h1>Cloud Settings</h1>

      <section style={{ marginTop: 16 }}>
        <h2>Providers & Credentials</h2>

        <div style={card}>
          <div
            style={{
              display: "flex",
              justifyContent: "space-between",
              alignItems: "center",
              marginBottom: 10,
            }}
          >
            <div style={{ fontWeight: 600, color: "#111827" }}>
              Configured Providers
            </div>
          </div>

          {/* TABLE */}
          <table
            style={{
              width: "100%",
              borderCollapse: "collapse",
              marginBottom: 14,
            }}
          >
            <thead>
              <tr>
                <th style={th}>Provider</th>
                <th style={th}>Instance Name</th>
                <th style={th}>Region / Endpoint</th>
                <th style={th}>Status</th>
                <th style={th}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan={5} style={{ textAlign: "center", padding: 16 }}>
                    Loading Provider Details…
                  </td>
                </tr>
              ) : providersList.length > 0 ? (
                providersList.map((p) => (
                  <tr
                    key={p.name}
                    style={{
                      backgroundColor:
                        editingProvider === p.name ? "#dbeafe" : "transparent",
                      boxShadow:
                        editingProvider === p.name
                          ? "0 0 0 1px #60a5fa inset"
                          : "none",
                      transition: "0.2s",
                    }}
                  >
                    <td style={td}>{p.provider}</td>
                    <td style={td}>{p.name}</td>
                    <td style={td}>{p.region}</td>

                    <td
                      style={{
                        ...td,
                        color: p.status === "Healthy" ? "#16a34a" : "#dc2626",
                        fontWeight: 600,
                      }}
                    >
                      {p.status}
                    </td>

                    <td style={td}>
                      <div style={{ display: "flex", gap: 8 }}>
                        {/* Edit */}
                        <button
                          onClick={() => handleEdit(p)}
                          className={layoutStyles.iconBtn}
                          title="Edit"
                        >
                          <img src="/assets/edit.ico" alt="Edit" width={16} height={16} />
                        </button>

                        {/* Delete */}
                        <button
                          onClick={() => {
                            if (
                              window.confirm(
                                `Delete provider instance "${p.name}"?`
                              )
                            ) {
                              handleDelete(p.name);
                            }
                          }}
                          className={layoutStyles.iconBtn}
                          title="Delete"
                        >
                          <img
                            src="/assets/delete.ico"
                            alt="Delete"
                            width={16}
                            height={16}
                          />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))
              ) : (
                <tr>
                  <td colSpan={5} style={{ textAlign: "center", padding: 16 }}>
                    No providers configured
                  </td>
                </tr>
              )}
            </tbody>
          </table>

          {/* FORM */}
          <div
            style={{
              display: "grid",
              gap: 12,
              gridTemplateColumns: "repeat(auto-fit, minmax(240px, 1fr))",
            }}
          >
            <label style={label}>
              Provider
              <select
                style={select}
                value={form.provider}
                onChange={(e) =>
                  setForm({ ...form, provider: e.target.value })
                }
              >
                <option value="">Select Provider</option>
                <option value="s3">AWS S3</option>
                <option value="azureblob">Azure Blob</option>
                <option value="drive">Google Drive</option>
              </select>
            </label>
            {/* 
            <label style={label}>
              Instance Name
              <input
                style={input}
                value={form.instanceName}
                onChange={(e) =>
                  setForm({ ...form, instanceName: e.target.value })
                }
              />
            </label> */}

            <label style={label}>
              Instance Name
              <input
                style={{
                  ...input,
                  backgroundColor: isEdit ? "#f3f4f6" : "white",
                  cursor: isEdit ? "not-allowed" : "text",
                }}
                value={form.instanceName}
                readOnly={isEdit}
                onChange={(e) =>
                  setForm({ ...form, instanceName: e.target.value })
                }
              />
            </label>


            <label style={label}>
              Region / Endpoint
              <input
                style={input}
                value={form.region}
                onChange={(e) =>
                  setForm({ ...form, region: e.target.value })
                }
              />
            </label>

            <label style={label}>
              Access Key
              <input
                style={input}
                value={form.accessKey}
                onChange={(e) =>
                  setForm({ ...form, accessKey: e.target.value })
                }
              />
            </label>

            {/* Secret + Clear */}
            <div style={{ display: "flex", gap: 8, alignItems: "flex-end" }}>
              <label style={{ ...label, flex: 1 }}>
                Secret Key
                <input
                  type="password"
                  style={input}
                  value={form.secretKey}
                  onChange={(e) =>
                    setForm({ ...form, secretKey: e.target.value })
                  }
                  placeholder="••••••••"
                />
              </label>

              <button
                style={{
                  height: "2.2rem",
                  padding: "0 14px",
                  borderRadius: 8,
                  border: "1px solid #d1d5db",
                  background: "#e5edff",
                  cursor: "pointer",
                  whiteSpace: "nowrap",
                }}
                onClick={resetForm}
              >
                Clear
              </button>
            </div>
          </div>

          <div style={{ marginTop: 10 }}>
            <button
              style={{
                padding: "9px 12px",
                borderRadius: 8,
                border: "1px solid #d1d5db",
                background: isEdit ? "#fde68a" : "#e5edff",
                cursor: "pointer",
              }}
              onClick={isEdit ? handleUpdate : handleSave}
            >
              {isEdit ? "Update Provider" : "+ Add Provider"}
            </button>
          </div>
        </div>
      </section>

      <section style={{ marginTop: 18 }}>
        <h2>Transfer Policies</h2>
        <div style={card}>
          <div style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))' }}>
            <label style={label}>
              Transfer Mode
              <select
                style={select}
                value={data.mode}
                onChange={e => setData({ ...data, mode: e.target.value })}
              >
                <option>After every backup</option>
                <option>Scheduled window</option>
                <option>Manual only</option>
              </select>
            </label>

            <label style={label}>
              Bandwidth Limit (MB/s)
              <input
                style={input}
                value={data.bandwidth}
                onChange={e => setData({ ...data, bandwidth: e.target.value })}
              />
            </label>

            <label style={label}>
              Retries
              <input
                style={input}
                value={data.retries}
                onChange={e => setData({ ...data, retries: e.target.value })}
              />
            </label>

            <label style={label}>
              Parallel Uploads
              <input
                style={input}
                value={data.parallel}
                onChange={e => setData({ ...data, parallel: e.target.value })}
              />
            </label>
          </div>

          <button
            onClick={savePolicies}
            style={{
              marginTop: 16,
              padding: "8px 16px",
              background: "rgb(37, 99, 235)",
              color: "rgb(255, 255, 255)",
              border: "none",
              borderRadius: 6,
              fontWeight: 500,
              cursor: "pointer"
            }}
          >
            Save Policies
          </button>

        </div>
      </section>

      <section style={{ marginTop: 18 }}>
        <h2 style={{ marginBottom: 12 }}>Scheduled Jobs</h2>

        <div
          style={{
            background: '#fff',
            borderRadius: 8,
            boxShadow: '0 2px 8px rgba(0,0,0,0.08)',
            overflowX: 'auto'
          }}
        >
          <table
            style={{
              width: '100%',
              borderCollapse: 'collapse',
              minWidth: 800
            }}
          >
            <thead>
              <tr>
                {['Name', 'Schedule', 'Scope', 'Next Run'].map(h => (
                  <th
                    key={h}
                    style={{
                      textAlign: 'left',
                      padding: '12px 10px',
                      background: '#f5f7fa',
                      fontWeight: 600,
                      fontSize: 14,
                      borderBottom: '1px solid #ddd'
                    }}
                  >
                    {h}
                  </th>
                ))}
              </tr>
            </thead>

            <tbody>
              {/* {schedule.map((row, i) => ( */}
              <tr>
                <td style={{ padding: 8 }}>
                  <input
                    style={inputStyle}
                    value={schedule.name}
                    onChange={updateRow}
                    name="name"
                  // onChange={e => updateRow(i, 'name', e.target.value)}
                  />
                </td>

                <td style={{ padding: 8 }}>
                  <input
                    style={inputStyle}
                    value={schedule.cron}
                    onChange={updateRow}
                    name="cron"
                    // onChange={e => updateRow(i, 'cron', e.target.value)}
                    placeholder="0 2 * * *"
                  />
                </td>

                <td style={{ padding: 8 }}>
                  <select
                    style={inputStyle}
                    value='system'
                    onChange={updateRow}

                  // onChange={e => updateRow(i, 'scope', e.target.value)}
                  >
                    <option value="system">All</option>
                    {/* <option value="user">User</option> */}
                  </select>
                </td>

                <td style={{ padding: 8 }}>
                  <input
                    style={{
                      ...inputStyle,
                      background: '#f0f0f0',
                      color: '#666',
                      cursor: 'not-allowed'
                    }}
                    placeholder="Tomorrow 02:00 AM"
                    value={schedule.next_run}
                    disabled
                  />
                </td>
              </tr>
              {/* ))} */}
            </tbody>
          </table>

          <div
            style={{
              padding: 12,
              borderTop: '1px solid #eee',
              textAlign: 'right'
            }}
          >
            <button
              onClick={handleSaveSchedule}
              style={{
                padding: '8px 16px',
                background: '#2563eb',
                color: '#fff',
                border: 'none',
                borderRadius: 6,
                fontWeight: 500,
                cursor: 'pointer'
              }}
            >
              Save Schedule
            </button>
          </div>
        </div>
      </section>

      {/* <section style={{ marginTop: 18 }}>
        <h2>Transfer Schedule</h2>
        <div style={card}>
          <div style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))' }}>
            <label style={label}>
              Mode (Global)
              <select disabled style={select}>
                <option>After every backup</option>
                <option>Cron-based</option>
                <option>Manual only</option>
              </select>
            </label>
            <label style={label}>
              Cron (Global)
              <input disabled style={input} placeholder="0 2 * * *" />
              <span style={hint}>Example: daily at 02:00.</span>
            </label>
            <label style={label}>
              Window (Global)
              <input disabled style={input} placeholder="02:00-04:00" />
              <span style={hint}>Optional transfer window.</span>
            </label>
            <label style={label}>
              Bandwidth Cap (MB/s)
              <input disabled style={input} placeholder="50" />
            </label>
          </div>
          {/* <div style={{ marginTop: 10, ...hint }}>
            Cron and window are UI-only; backend will enforce schedule later.
          </div> */}
      {/* </div>
      </section> */}

      <section style={{ marginTop: 18, display: 'none' }}>
        <h2>Per-Host Overrides</h2>
        <div style={card}>
          <table style={{ width: '100%', borderCollapse: 'collapse' }}>
            <thead>
              <tr>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Host</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Mode</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Cron</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Window</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {hosts.map(row => (
                <tr key={row.host}>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>{row.host}</td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <select disabled style={select}>
                      <option selected={row.schedule === 'inherit'}>Inherit global</option>
                      <option selected={row.schedule === 'custom'}>Custom</option>
                    </select>
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <input disabled style={input} placeholder={row.cron} />
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <input disabled style={input} placeholder={row.window} />
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                      <button style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d1d5db', background: '#e5edff', cursor: 'not-allowed' }}>Set custom</button>
                      <button style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d1d5db', background: '#f0fdf4', cursor: 'not-allowed' }}>Revert to global</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {/* <div style={{ marginTop: 10, ...hint }}>
            Overrides are UI-only; when wired, selecting “Custom” should enable per-host cron/window and save to backend.
          </div> */}
        </div>
      </section>

      {/* <section style={{ marginTop: 18 }}>
        <h2>Provider Assignment</h2>
        <div style={card}>
          <div style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))' }}>
            <label style={label}>
              Default Provider (Global)
              <select disabled style={select}>
                <option>AWS S3</option>
                <option>Azure Blob</option>
                <option>GCS</option>
                <option>S3-compatible</option>
              </select>
              <span style={hint}>Applies to all hosts unless overridden.</span>
            </label>
            <label style={label}>
              Secondary / Standby (Global)
              <select disabled style={select}>
                <option>None</option>
                <option>AWS S3</option>
                <option>Azure Blob</option>
                <option>GCS</option>
              </select>
              <span style={hint}>Optional fallback target.</span>
            </label>
          </div>
          <div style={{ marginTop: 14, fontWeight: 600, color: '#111827' }}>Per-Host Overrides</div>
          <table style={{ width: '100%', borderCollapse: 'collapse', marginTop: 8 }}>
            <thead>
              <tr>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Host</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Mode</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Provider</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Secondary</th>
                <th style={{ textAlign: 'left', padding: '8px', borderBottom: '1px solid #e5e7eb', color: '#6b7280', fontWeight: 600 }}>Actions</th>
              </tr>
            </thead>
            <tbody>
              {providerAssignments.map(row => (
                <tr key={row.host}>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>{row.host}</td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <select disabled style={select}>
                      <option selected={row.mode === 'inherit'}>Inherit global</option>
                      <option selected={row.mode === 'custom'}>Custom</option>
                    </select>
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <select disabled style={select}>
                      <option selected={row.provider === 'AWS S3'}>AWS S3</option>
                      <option selected={row.provider === 'Azure Blob'}>Azure Blob</option>
                      <option selected={row.provider === 'GCS'}>GCS</option>
                      <option selected={row.provider === 'S3-compatible'}>S3-compatible</option>
                    </select>
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <select disabled style={select}>
                      <option selected={row.secondary === '—'}>None</option>
                      <option selected={row.secondary === 'AWS S3'}>AWS S3</option>
                      <option selected={row.secondary === 'Azure Blob'}>Azure Blob</option>
                      <option selected={row.secondary === 'GCS'}>GCS</option>
                    </select>
                  </td>
                  <td style={{ padding: '8px', borderBottom: '1px solid #e5e7eb' }}>
                    <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                      <button style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d1d5db', background: '#e5edff', cursor: 'not-allowed' }}>Set custom</button>
                      <button style={{ padding: '7px 10px', borderRadius: 8, border: '1px solid #d1d5db', background: '#f0fdf4', cursor: 'not-allowed' }}>Revert to global</button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <div style={{ marginTop: 10, ...hint }}>
            Provider assignments are UI-only; wire to backend to save defaults and per-host overrides.
          </div>
        </div>
      </section> */}

      {/* <section style={{ marginTop: 18 }}>
        <h2>Retention & Lifecycle</h2>
        <div style={card}>
          <div style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(220px, 1fr))' }}>
            <label style={label}>
              Cloud Retention (days)
              <input disabled style={input} placeholder="90" />
            </label>
            <label style={label}>
              Mirror Local Deletions
              <select disabled style={select}>
                <option>Enabled</option>
                <option>Disabled</option>
              </select>
            </label>
            <label style={label}>
              Archive to Cold Storage after (days)
              <input disabled style={input} placeholder="30" />
            </label>
          </div>
          <div style={{ marginTop: 10, ...hint }}>
            Lifecycle controls are UI-only; hook to provider policies later.
          </div>
        </div>
      </section> */}

      {/* <section style={{ marginTop: 18 }}>
        <h2>Restore Behavior</h2>
        <div style={card}>
          <div style={{ display: 'grid', gap: 12, gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))' }}>
            <label style={label}>
              Rehydrate from Cloud if Missing
              <select disabled style={select}>
                <option>Yes</option>
                <option>No</option>
              </select>
            </label>
            <label style={label}>
              Staging Path
              <input disabled style={input} placeholder="/var/lib/backuppc/cloud-staging" />
            </label>
            <label style={label}>
              Verify Checksums After Download
              <select disabled style={select}>
                <option>Yes</option>
                <option>No</option>
              </select>
            </label>
          </div>
          <div style={{ marginTop: 10, ...hint }}>
            Restore options are UI-only; connect to restore workflow later.
          </div>
        </div>
      </section> */}
    </div>
  )
}

export default CloudSettings

