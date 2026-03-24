import { momentsData, currentUser } from '../data/mock';

interface Props { onBack: () => void; }

export default function MomentsPage({ onBack }: Props) {
  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 70, background: '#ededed', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 44, background: '#ededed', flexShrink: 0, paddingTop: 'env(safe-area-inset-top)' }}>
        <button onClick={onBack} style={{ width: 48, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer', flexShrink: 0 }}>
          <svg width="12" height="20" viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10L10 18" stroke="#111" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: '#111', paddingRight: 48 }}>朋友圈</div>
      </div>

      <div className="no-scrollbar" style={{ flex: 1, overflowY: 'auto', paddingBottom: 64 }}>
        <div style={{ height: 250, background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)', position: 'relative', display: 'flex', alignItems: 'flex-end', justifyContent: 'flex-end', padding: 12 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ fontSize: 15, color: '#fff', fontWeight: 500, textShadow: '0 1px 3px rgba(0,0,0,0.3)' }}>微信用户</span>
            <div style={{ width: 60, height: 60, borderRadius: 4, border: '2px solid #fff', overflow: 'hidden', boxShadow: '0 2px 8px rgba(0,0,0,0.2)' }}>
              <img src={currentUser.avatar} alt="" style={{ width: 60, height: 60 }} />
            </div>
          </div>
        </div>

        {momentsData.map((mom, idx) => (
          <div key={mom.id} style={{ background: '#fff', padding: '12px 12px 12px 68px', position: 'relative', borderBottom: idx < momentsData.length - 1 ? '0.5px solid #e7e7e7' : 'none' }}>
            <div style={{ position: 'absolute', left: 12, top: 12, width: 40, height: 40, borderRadius: 4, overflow: 'hidden' }}>
              <img src={mom.avatar} alt={mom.userName} style={{ width: 40, height: 40, display: 'block' }} />
            </div>
            <div style={{ fontSize: 14.5, fontWeight: 600, color: '#576b95', marginBottom: 4 }}>{mom.userName}</div>
            <div style={{ fontSize: 15, color: '#111', lineHeight: 1.4, wordBreak: 'break-word', marginBottom: 6 }}>{mom.content}</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 12, color: '#b2b2b2' }}>
              <span>{mom.time}</span>
              {mom.location && <span style={{ color: '#576b95' }}>{mom.location}</span>}
            </div>
            {(mom.likes.length > 0 || mom.comments.length > 0) && (
              <div style={{ marginTop: 8, background: '#f3f3f3', borderRadius: 3, padding: '6px 8px' }}>
                {mom.likes.length > 0 && (
                  <div style={{ fontSize: 13, color: '#576b95', marginBottom: mom.comments.length > 0 ? 6 : 0, display: 'flex', alignItems: 'center', gap: 4, flexWrap: 'wrap' }}>
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="#576b95"><path d="M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"/></svg>
                    {mom.likes.join('、')}
                  </div>
                )}
                {mom.comments.map((c, i) => (
                  <div key={i} style={{ fontSize: 13, lineHeight: 1.4, color: '#111', borderTop: i > 0 || mom.likes.length > 0 ? '0.5px solid #ddd' : 'none', paddingTop: i > 0 || mom.likes.length > 0 ? 6 : 0 }}>
                    <span style={{ color: '#576b95', fontWeight: 500 }}>{c.user}</span><span>: {c.text}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
