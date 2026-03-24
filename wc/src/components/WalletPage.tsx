interface Props { onBack: () => void; }

const ListRow: React.CSSProperties = { display: 'flex', alignItems: 'center', padding: '12px 11px', background: '#fff', width: '100%', border: 'none', cursor: 'pointer', fontSize: 16, textAlign: 'left' };
const RowIcon: React.CSSProperties = { width: 24, height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 };
const Chev = () => <svg width="8" height="13" viewBox="0 0 8 13" fill="none"><path d="M1 1l5.5 5.5L1 12" stroke="#c7c7cc" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>;

const walletItems = [
  [{ id: 'pay', icon: '💳', label: '收付款' }],
  [{ id: 'change', icon: '💰', label: '钱包' }],
  [{ id: 'cards', icon: '🎫', label: '信用卡还款' }, { id: 'mobile', icon: '📱', label: '手机充值' }, { id: 'transfer', icon: '🏦', label: '亲属卡' }],
  [{ id: 'ticket', icon: '🚂', label: '火车票机票' }, { id: 'movie', icon: '🎬', label: '电影演出' }, { id: 'nearby', icon: '📍', label: '城市服务' }],
  [{ id: 'finance', icon: '📊', label: '金融理财' }, { id: 'insurance', icon: '🛡️', label: '保险服务' }],
];

export default function WalletPage({ onBack }: Props) {
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 70, background: '#ededed', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 44, background: '#ededed', flexShrink: 0, paddingTop: 'env(safe-area-inset-top)' }}>
        <button onClick={onBack} style={{ width: 48, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer', flexShrink: 0 }}>
          <svg width="12" height="20" viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10L10 18" stroke="#111" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: '#111', paddingRight: 48 }}>支付</div>
      </div>
      <div className="no-scrollbar" style={{ flex: 1, overflowY: 'auto', paddingBottom: 64 }}>
        <div style={{ margin: '10px 11px', padding: '16px', background: 'linear-gradient(135deg, #2d3436 0%, #000000 100%)', borderRadius: 8, color: '#fff' }}>
          <div style={{ fontSize: 13, opacity: 0.7, marginBottom: 4 }}>零钱</div>
          <div style={{ fontSize: 28, fontWeight: 600, marginBottom: 2 }}>¥0.00</div>
          <div style={{ fontSize: 12, opacity: 0.5 }}>本服务由财付通提供</div>
        </div>
        {walletItems.map((group, gi) => (
          <div key={gi}>
            {gi > 0 && <div style={{ height: 8, background: '#ededed' }} />}
            {group.map(item => (
              <div key={item.id} style={ListRow}>
                <span style={RowIcon}>{item.icon}</span>
                <span style={{ flex: 1, marginLeft: 12, color: '#111' }}>{item.label}</span>
                <Chev />
              </div>
            ))}
          </div>
        ))}
        <div style={{ textAlign: 'center', fontSize: 12, color: '#b2b2b2', padding: '20px 0' }}>本服务由财付通提供</div>
      </div>
    </div>
  );
}
