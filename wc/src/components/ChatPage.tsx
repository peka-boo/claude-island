import { useState, useRef, useEffect } from 'react';
import { currentUser } from '../data/mock';
import type { Message, ChatUser } from '../data/mock';

const unicodeEmojis = [
  '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇','🥰','😍','🤩',
  '😘','😗','😚','😙','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','🤨',
  '😐','😑','😶','😏','😒','🙄','😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕',
  '🤢','🤮','🤧','🥵','🥶','🥴','😵','🤯','🤠','🥳','🥸','😎','🤓','🧐','😕','😟',
  '🙁','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭','😱','😖','😣',
  '😞','😓','😩','😫','🥱','😤','😡','😠','🤬','😈','👿','💀','☠️','💩','🤡','👹',
  '👺','👻','👽','👾','🤖','😺','😸','😹','😻','😼','😽','🙀','😿','😾','❤️','🧡',
  '💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞','💓','💗','💖','💘','💝',
  '👍','👎','👊','✊','🤛','🤜','🤞','✌️','🤟','🤘','👌','🤌','🤏','👈','👉','👆',
  '👇','☝️','✋','🤚','🖐️','🖖','👋','🤙','💪','🦾','🙏','🤝','💅','👂','🦻','👃',
];

interface Props { user: ChatUser; messages: Message[]; onBack: () => void; onSend: (text: string) => void; }

export default function ChatPage({ user, messages, onBack, onSend }: Props) {
  const [inputText, setInputText] = useState('');
  const [showEmoji, setShowEmoji] = useState(false);
  const [showMore, setShowMore] = useState(false);
  const endRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => { endRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages]);

  const handleSend = () => {
    if (!inputText.trim()) return;
    onSend(inputText.trim());
    setInputText('');
    setShowEmoji(false);
    setShowMore(false);
  };

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 60, background: '#ededed', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', height: 44, background: '#ededed', borderBottom: '0.5px solid #d9d9d9', flexShrink: 0, paddingTop: 'env(safe-area-inset-top)' }}>
        <button onClick={onBack} style={{ width: 48, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer', flexShrink: 0 }}>
          <svg width="12" height="20" viewBox="0 0 12 20" fill="none"><path d="M10 2L2 10L10 18" stroke="#111" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
        </button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 17, fontWeight: 600, color: '#111', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', paddingRight: 48 }}>{user.name}</div>
        <button style={{ width: 44, height: 44, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer', flexShrink: 0 }}>
          <svg width="20" height="20" viewBox="0 0 20 20" fill="none"><circle cx="4" cy="10" r="1.5" fill="#111"/><circle cx="10" cy="10" r="1.5" fill="#111"/><circle cx="16" cy="10" r="1.5" fill="#111"/></svg>
        </button>
      </div>

      <div className="no-scrollbar" style={{ flex: 1, overflowY: 'auto', padding: '8px 11px', WebkitOverflowScrolling: 'touch' }}>
        {messages.map(msg => {
          const isMe = msg.sender === 'me';
          if (msg.type === 'system') {
            return <div key={msg.id} style={{ textAlign: 'center', fontSize: 12, color: '#b2b2b2', padding: '5px 0' }}>{msg.content}</div>;
          }
          return (
            <div key={msg.id} style={{ display: 'flex', marginBottom: 13, flexDirection: isMe ? 'row-reverse' : 'row', alignItems: 'flex-start' }}>
              <div style={{ width: 40, height: 40, borderRadius: 4, overflow: 'hidden', flexShrink: 0 }}>
                <img src={isMe ? currentUser.avatar : (msg.senderAvatar || user.avatar)} alt="" style={{ width: 40, height: 40, display: 'block', background: '#ddd' }} />
              </div>
              <div style={{ maxWidth: '65%', marginLeft: isMe ? 0 : 10, marginRight: isMe ? 10 : 0 }}>
                {msg.type === 'text' && (
                  <div style={{ position: 'relative', background: isMe ? '#95ec69' : '#fff', borderRadius: 4, fontSize: 15.5, padding: '9px 11px', lineHeight: '21px', wordBreak: 'break-word', color: '#111' }}>
                    <div style={{ position: 'absolute', top: 14, width: 8, height: 8, background: isMe ? '#95ec69' : '#fff', transform: 'rotate(45deg)', ...(isMe ? { right: -4 } : { left: -4 }) }} />
                    {msg.content}
                  </div>
                )}
                {msg.type === 'file' && (
                  <div style={{ background: isMe ? '#95ec69' : '#fff', borderRadius: 4, padding: '9px 11px', position: 'relative', minWidth: 200 }}>
                    <div style={{ position: 'absolute', top: 14, width: 8, height: 8, background: isMe ? '#95ec69' : '#fff', transform: 'rotate(45deg)', ...(isMe ? { right: -4 } : { left: -4 }) }} />
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <svg width="28" height="28" viewBox="0 0 24 24" fill="#576b95"><path d="M14 2H6c-1.1 0-2 .9-2 2v16c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V8l-6-6zm4 18H6V4h7v5h5v11z"/></svg>
                      <div><div style={{ fontSize: 14, color: '#111' }}>{msg.fileName}</div><div style={{ fontSize: 12, color: '#888' }}>{msg.fileSize}</div></div>
                    </div>
                  </div>
                )}
                {msg.type === 'image' && (
                  <div style={{ background: '#fff', borderRadius: 4, padding: 4, position: 'relative' }}>
                    <div style={{ position: 'absolute', top: 14, width: 8, height: 8, background: '#fff', transform: 'rotate(45deg)', ...(isMe ? { right: -4 } : { left: -4 }) }} />
                    <div style={{ width: 170, height: 120, background: '#e5e5e5', borderRadius: 2, display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#999', fontSize: 12 }}>图片</div>
                  </div>
                )}
                {msg.type === 'emoji' && (
                  <div style={{ position: 'relative' }}>
                    <div style={{ position: 'absolute', top: 14, width: 8, height: 8, background: 'transparent', ...(isMe ? { right: -4 } : { left: -4 }) }} />
                    <span style={{ fontSize: 80, lineHeight: 1 }}>{msg.content}</span>
                  </div>
                )}
                <div style={{ fontSize: 10.5, color: '#b2b2b2', marginTop: 4, textAlign: isMe ? 'right' : 'left' }}>{msg.time}</div>
              </div>
            </div>
          );
        })}
        <div ref={endRef} />
      </div>

      <div style={{ flexShrink: 0, background: '#f6f6f6', borderTop: '0.5px solid #ddd' }}>
        <div style={{ display: 'flex', alignItems: 'flex-end', padding: '8px 10px', gap: 6 }}>
          <button style={{ width: 34, height: 34, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, background: 'none', border: 'none', cursor: 'pointer' }}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="#333"><path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3z"/><path d="M17 11c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z"/></svg>
          </button>
          <div style={{ flex: 1, background: '#fff', borderRadius: 5, border: '0.5px solid #ddd', minHeight: 34, display: 'flex', alignItems: 'flex-end' }}>
            <input ref={inputRef} type="text" value={inputText} onChange={e => setInputText(e.target.value)}
              onFocus={() => { setShowEmoji(false); setShowMore(false); }}
              onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); handleSend(); }}}
              placeholder="" style={{ flex: 1, padding: '7px 8px', fontSize: 15, background: 'transparent', border: 'none', outline: 'none', lineHeight: '1.3' }} />
          </div>
          <button onClick={() => { setShowEmoji(!showEmoji); setShowMore(false); }} style={{ width: 34, height: 34, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, background: 'none', border: 'none', cursor: 'pointer' }}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="#333"><path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-4-8c.79 0 1.5-.71 1.5-1.5S8.79 9 8 9s-1.5.71-1.5 1.5S7.21 12 8 12zm8 0c.79 0 1.5-.71 1.5-1.5S16.79 9 16 9s-1.5.71-1.5 1.5.71 1.5 1.5 1.5zm-4 4c2.21 0 4-1.79 4-4h-8c0 2.21 1.79 4 4 4z"/></svg>
          </button>
          <button onClick={() => { setShowMore(!showMore); setShowEmoji(false); }} style={{ width: 34, height: 34, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0, background: 'none', border: 'none', cursor: 'pointer' }}>
            <svg width="26" height="26" viewBox="0 0 24 24" fill="#333"><path d="M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z"/></svg>
          </button>
          {inputText.trim() && (
            <button onClick={handleSend} style={{ background: '#07c160', color: '#fff', padding: '5px 10px', borderRadius: 4, fontSize: 14, fontWeight: 500, border: 'none', cursor: 'pointer', flexShrink: 0, whiteSpace: 'nowrap' }}>发送</button>
          )}
        </div>

        {showEmoji && (
          <div style={{ height: 230, background: '#fff', borderTop: '0.5px solid #ddd', overflowY: 'auto', padding: '8px 4px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(8, 1fr)', gap: 2 }}>
              {unicodeEmojis.map((emoji, i) => (
                <button key={i} onClick={() => { setInputText(prev => prev + emoji); inputRef.current?.focus(); }}
                  style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 6, fontSize: 26, borderRadius: 4, background: 'none', border: 'none', cursor: 'pointer' }}>
                  {emoji}
                </button>
              ))}
            </div>
          </div>
        )}

        {showMore && (
          <div style={{ height: 180, background: '#fff', borderTop: '0.5px solid #ddd', padding: '12px 8px' }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 10 }}>
              {[
                { icon: '📷', label: '照片' }, { icon: '📸', label: '拍摄' },
                { icon: '📹', label: '视频通话' }, { icon: '📍', label: '位置' },
                { icon: '📄', label: '文件' }, { icon: '👤', label: '名片' },
                { icon: '🎵', label: '音乐' }, { icon: '🔗', label: '链接' },
              ].map(item => (
                <button key={item.label} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, background: 'none', border: 'none', cursor: 'pointer' }}>
                  <div style={{ width: 50, height: 50, background: '#f4f4f4', borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 24 }}>{item.icon}</div>
                  <span style={{ fontSize: 11, color: '#888' }}>{item.label}</span>
                </button>
              ))}
            </div>
          </div>
        )}

        <div style={{ paddingBottom: 'env(safe-area-inset-bottom)' }} />
      </div>
    </div>
  );
}
