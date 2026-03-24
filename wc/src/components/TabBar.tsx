interface TabBarProps { active: string; onTabChange: (tab: string) => void; unread?: number; }

const S: Record<string, React.CSSProperties> = {
  wrap: { position: 'fixed', bottom: 0, left: 0, width: '100%', zIndex: 50, background: '#fff', paddingBottom: 'env(safe-area-inset-bottom)' },
  bar: { display: 'flex', height: 49, borderTop: '0.5px solid #d9d9d9' },
  btn: { flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', position: 'relative', border: 'none', background: 'none', padding: 0, gap: 2, cursor: 'pointer' },
  label: (on: boolean): React.CSSProperties => ({ fontSize: 10.5, color: on ? '#46c365' : '#999', lineHeight: 1 }),
  badge: { position: 'absolute', top: -3, right: -8, minWidth: 16, height: 16, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, color: '#fff', background: '#f84241', borderRadius: 16, padding: '0 4px', fontWeight: 600, fontFamily: 'system-ui, Arial, sans-serif' },
};

export default function TabBar({ active, onTabChange, unread = 0 }: TabBarProps) {
  const tabs = [
    { id: 'chats', label: '微信', icon: 'tab_1.png' },
    { id: 'contacts', label: '通讯录', icon: 'tab_2.png' },
    { id: 'discover', label: '发现', icon: 'tab_3.png' },
    { id: 'profile', label: '我', icon: 'tab_4.png' },
  ];
  return (
    <div style={S.wrap}>
      <div style={S.bar}>
        {tabs.map(tab => {
          const on = active === tab.id;
          return (
            <button key={tab.id} style={S.btn} onClick={() => onTabChange(tab.id)}>
              <div style={{ position: 'relative', width: 28, height: 28, backgroundImage: `url(/assets/${tab.icon})`, backgroundSize: '100% auto', backgroundPosition: on ? '0 100%' : '0 0', backgroundRepeat: 'no-repeat' }}>
                {tab.id === 'chats' && unread > 0 && <span style={S.badge}>{unread > 99 ? '99+' : unread}</span>}
              </div>
              <span style={S.label(on)}>{tab.label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
