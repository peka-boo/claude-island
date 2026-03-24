import { useState, useRef, useCallback } from 'react';
import type { ChatUser } from '../data/mock';

interface Props { user: ChatUser; onClick: () => void; onDelete: () => void; }

export default function ChatCell({ user, onClick, onDelete }: Props) {
  const [offset, setOffset] = useState(0);
  const startX = useRef(0);
  const swiping = useRef(false);

  const onTouchStart = useCallback((e: React.TouchEvent) => { startX.current = e.touches[0].clientX; swiping.current = true; }, []);
  const onTouchMove = useCallback((e: React.TouchEvent) => {
    if (!swiping.current) return;
    const diff = startX.current - e.touches[0].clientX;
    setOffset(diff > 0 ? Math.min(diff, 80) : 0);
  }, []);
  const onTouchEnd = useCallback(() => { swiping.current = false; setOffset(prev => (prev > 40 ? 80 : 0)); }, []);

  return (
    <div style={{ position: 'relative', overflow: 'hidden', background: '#fff' }}>
      <button onClick={e => { e.stopPropagation(); onDelete(); }} style={{ position: 'absolute', right: 0, top: 0, height: '100%', width: 80, background: '#ff3b30', color: '#fff', fontSize: 16, fontWeight: 500, display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1, border: 'none', cursor: 'pointer' }}>删除</button>
      <div style={{ display: 'flex', alignItems: 'center', padding: '10px 11px', position: 'relative', zIndex: 2, transform: `translateX(-${offset}px)`, transition: swiping.current ? 'none' : 'transform 0.25s ease', background: '#fff' }}
        onTouchStart={onTouchStart} onTouchMove={onTouchMove} onTouchEnd={onTouchEnd}
        onClick={() => { if (offset > 0) { setOffset(0); return; } onClick(); }}>
        <div style={{ flexShrink: 0, borderRadius: 4, overflow: 'hidden', width: 48, height: 48 }}>
          <img src={user.avatar} alt={user.name} style={{ width: 48, height: 48, display: 'block' }} />
        </div>
        <div style={{ flex: 1, marginLeft: 11, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <span style={{ fontSize: 16, color: '#111', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{user.name}</span>
            <span style={{ fontSize: 12, color: '#b2b2b2', flexShrink: 0, marginLeft: 8 }}>{user.time}</span>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 4 }}>
            <span style={{ fontSize: 13, color: '#888', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', flex: 1 }}>{user.lastMessage}</span>
            {user.unread > 0 && (
              <span style={{ flexShrink: 0, marginLeft: 8, minWidth: 17, height: 17, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, color: '#fff', background: '#f84241', borderRadius: 17, padding: '0 4px', fontWeight: 600, fontFamily: 'system-ui, Arial, sans-serif' }}>{user.unread > 99 ? '99+' : user.unread}</span>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
