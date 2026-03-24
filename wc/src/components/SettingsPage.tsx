interface Props { onBack: () => void; }

const ListRow: React.CSSProperties = { display: 'flex', alignItems: 'center', padding: '12px 11px', background: '#fff', width: '100%', border: 'none', cursor: 'pointer', fontSize: 16, textAlign: 'left' };
const Chev = () => <svg width="8" height="13" viewBox="0 0 8 13" fill="none"><path d="M1 1l5.5 5.5L1 12" stroke="#c7c7cc" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>;

const settingsGroups = [
  [{ id: 'account', label: '帐号与安全' }],
  [{ id: 'newmsg', label: '新消息通知' }, { id: 'privacy', label: '隐私' }, { id: 'general', label: '通用' }],
  [{ id: 'help', label: '帮助与反馈' }, { id: 'about', label: '关于微信' }],
];

export default function SettingsPage({ onBack }: Props) {
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 70, background: '#ededed', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 44, background: '#ededed', flexShrink: 0, paddingTop: 'env(safe-area-inset-top)' }}>
        <button onClick={onBack} style={{ width: 48, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer', flexShrink: 0 }}>
          <svg width="12" height="20" viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10L10 18" stroke="#111" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: '#111', paddingRight: 48 }}>设置</div>
      </div>
      <div className="no-scrollbar" style={{ flex: 1, overflowY: 'auto', paddingBottom: 64 }}>
        {settingsGroups.map((group, gi) => (
          <div key={gi}>
            {gi > 0 && <div style={{ height: 8, background: '#ededed' }} />}
            {group.map(item => (
              <div key={item.id} style={ListRow}>
                <span style={{ flex: 1, color: '#111' }}>{item.label}</span>
                <Chev />
              </div>
            ))}
          </div>
        ))}
        <div style={{ height: 30 }} />
        <div style={{ padding: '0 11px' }}>
          <button style={{ width: '100%', padding: '12px 0', background: '#fff', border: 'none', borderRadius: 5, fontSize: 16, color: '#111', fontWeight: 500, cursor: 'pointer', textAlign: 'center' }}>退出登录</button>
        </div>
        <div style={{ textAlign: 'center', fontSize: 12, color: '#b2b2b2', padding: '16px 0' }}>Version 8.0.0</div>
      </div>
    </div>
  );
}
