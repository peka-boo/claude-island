import { useState, useCallback, useEffect } from 'react';
import TabBar from './components/TabBar';
import SearchBar from './components/SearchBar';
import ChatCell from './components/ChatCell';
import ChatPage from './components/ChatPage';
import ContactCell from './components/ContactCell';
import MomentsPage from './components/MomentsPage';
import SettingsPage from './components/SettingsPage';
import WalletPage from './components/WalletPage';
import {
  chatUsers as initialChatUsers, contacts, mockMessages,
  discoverItems, profileItems, currentUser, initAvatars,
} from './data/mock';
import type { ChatUser, Message } from './data/mock';

const HS: React.CSSProperties = {
  display: 'flex', alignItems: 'center', justifyContent: 'space-between',
  height: 44, padding: '0 11px', background: '#ededed',
};
const HT: React.CSSProperties = { fontSize: 17, fontWeight: 600, color: '#111' };
const HBtn: React.CSSProperties = {
  width: 44, height: 44, display: 'flex', alignItems: 'center',
  justifyContent: 'center', background: 'none', border: 'none', cursor: 'pointer',
};
const ListRow: React.CSSProperties = {
  display: 'flex', alignItems: 'center', padding: '12px 11px',
  background: '#fff', width: '100%', border: 'none', cursor: 'pointer',
  fontSize: 16, textAlign: 'left',
};
const RowIcon: React.CSSProperties = {
  width: 24, height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center',
  fontSize: 20, flexShrink: 0,
};
const Chev = () => (
  <svg width="8" height="13" viewBox="0 0 8 13" fill="none">
    <path d="M1 1l5.5 5.5L1 12" stroke="#c7c7cc" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);
const Badge = ({ n }: { n: number }) => (
  <span style={{
    minWidth: 17, height: 17, display: 'flex', alignItems: 'center',
    justifyContent: 'center', fontSize: 10, color: '#fff', background: '#f84241',
    borderRadius: 17, padding: '0 4px', fontWeight: 600, marginRight: 6,
    fontFamily: 'system-ui, Arial, sans-serif',
  }}>{n > 99 ? '99+' : n}</span>
);

export default function App() {
  const [activeTab, setActiveTab] = useState('chats');
  const [chatUsers, setChatUsers] = useState(initialChatUsers);
  const [activeChat, setActiveChat] = useState<ChatUser | null>(null);
  const [messages, setMessages] = useState<Record<string, Message[]>>(mockMessages);
  const [page, setPage] = useState<string | null>(null);
  useEffect(() => { initAvatars(); }, []);

  const totalUnread = chatUsers.reduce((s, u) => s + u.unread, 0);

  const handleDeleteChat = useCallback((id: string) => {
    setChatUsers(p => p.filter(u => u.id !== id));
  }, []);

  const handleSendMessage = useCallback((text: string) => {
    if (!activeChat) return;
    const msg: Message = {
      id: `m_${Date.now()}`, chatId: activeChat.id, type: 'text',
      content: text, sender: 'me',
      time: new Date().toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }),
    };
    setMessages(p => ({ ...p, [activeChat.id]: [...(p[activeChat.id] || []), msg] }));
    setChatUsers(p => p.map(u => u.id === activeChat.id ? { ...u, lastMessage: text, time: '刚刚' } : u));
  }, [activeChat]);

  const handleOpenChat = useCallback((user: ChatUser) => {
    setActiveChat(user);
    setChatUsers(p => p.map(u => u.id === user.id ? { ...u, unread: 0 } : u));
  }, []);

  const renderChats = () => (
    <div>
      <div style={HS}>
        <h1 style={HT}>微信</h1>
        <div style={{ display: 'flex', gap: 2 }}>
          <button style={HBtn}>
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke="#111" strokeWidth="1.8"/><path d="M16.5 16.5L21 21" stroke="#111" strokeWidth="1.8" strokeLinecap="round"/></svg>
          </button>
          <button style={HBtn}>
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><circle cx="5" cy="12" r="1.5" fill="#111"/><circle cx="12" cy="12" r="1.5" fill="#111"/><circle cx="19" cy="12" r="1.5" fill="#111"/></svg>
          </button>
        </div>
      </div>
      <SearchBar />
      <div style={{ paddingBottom: 64 }}>
        {chatUsers.map(user => (
          <ChatCell key={user.id} user={user} onClick={() => handleOpenChat(user)} onDelete={() => handleDeleteChat(user.id)} />
        ))}
      </div>
    </div>
  );

  const renderContacts = () => {
    const grouped = contacts.reduce((acc, c) => {
      if (c.type) { (acc['special'] ||= []).push(c); } else { (acc[c.letter] ||= []).push(c); }
      return acc;
    }, {} as Record<string, typeof contacts>);
    const letters = Object.keys(grouped).sort((a, b) => {
      if (a === 'special') return -1;
      if (b === 'special') return 1;
      return a.localeCompare(b);
    });
    return (
      <div>
        <div style={HS}>
          <h1 style={HT}>通讯录</h1>
          <div style={{ display: 'flex', gap: 2 }}>
            <button style={HBtn}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><circle cx="11" cy="11" r="7" stroke="#111" strokeWidth="1.8"/><path d="M16.5 16.5L21 21" stroke="#111" strokeWidth="1.8" strokeLinecap="round"/></svg>
            </button>
            <button style={HBtn}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none"><path d="M12 5v14M5 12h14" stroke="#111" strokeWidth="1.8" strokeLinecap="round"/></svg>
            </button>
          </div>
        </div>
        <SearchBar />
        <div style={{ paddingBottom: 64 }}>
          {letters.map(letter => (
            <div key={letter}>
              {letter !== 'special' && (
                <div style={{ padding: '2px 11px', fontSize: 13, color: '#888', background: '#ededed', fontWeight: 500, position: 'sticky', top: 0, zIndex: 10 }}>{letter}</div>
              )}
              {grouped[letter].map(c => (
                <ContactCell key={c.id} contact={c} onClick={() => {}} />
              ))}
            </div>
          ))}
          <div style={{ textAlign: 'center', fontSize: 13, color: '#888', padding: '14px 0', background: '#ededed' }}>
            {contacts.filter(c => !c.type).length}位联系人
          </div>
        </div>
      </div>
    );
  };

  const renderDiscover = () => (
    <div>
      <div style={HS}><h1 style={HT}>发现</h1></div>
      <div style={{ paddingBottom: 64 }}>
        {discoverItems.map(item => (
          <div key={item.id}>
            <div style={ListRow} onClick={() => { if (item.id === 'moments') setPage('moments'); }}>
              <span style={RowIcon}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="#576b95" dangerouslySetInnerHTML={{ __html: item.iconSvg }} />
              </span>
              <span style={{ flex: 1, marginLeft: 12, color: '#111' }}>{item.label}</span>
              {'badge' in item && item.badge ? <Badge n={item.badge} /> : null}
              <Chev />
            </div>
            {item.divider && <div style={{ height: 8, background: '#ededed' }} />}
          </div>
        ))}
      </div>
    </div>
  );

  const renderProfile = () => (
    <div>
      <div style={{
        display: 'flex', alignItems: 'center', padding: '30px 11px 20px',
        background: '#fff', paddingTop: 'calc(30px + env(safe-area-inset-top))',
      }}>
        <img src={currentUser.avatar} alt={currentUser.name} style={{ width: 64, height: 64, borderRadius: 6, flexShrink: 0 }} />
        <div style={{ marginLeft: 14, flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 18, fontWeight: 600, color: '#111' }}>{currentUser.name}</div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginTop: 6 }}>
            <span style={{ fontSize: 14, color: '#888' }}>微信号：{currentUser.wxid}</span>
            <Chev />
          </div>
          <span style={{ fontSize: 14, color: '#888', display: 'block', marginTop: 4 }}>{currentUser.region}</span>
        </div>
      </div>
      <div style={{ height: 8, background: '#ededed' }} />
      <div style={{ paddingBottom: 64 }}>
        {profileItems.map(item => (
          <div key={item.id}>
            <div style={ListRow} onClick={() => {
              if (item.id === 'pay') setPage('wallet');
              if (item.id === 'settings') setPage('settings');
            }}>
              <span style={RowIcon}>
                <svg width="24" height="24" viewBox="0 0 24 24" fill="#576b95" dangerouslySetInnerHTML={{ __html: item.iconSvg }} />
              </span>
              <span style={{ flex: 1, marginLeft: 12, color: '#111' }}>{item.label}</span>
              <Chev />
            </div>
            {item.divider && <div style={{ height: 8, background: '#ededed' }} />}
          </div>
        ))}
      </div>
    </div>
  );

  return (
    <div style={{ height: '100vh', background: '#ededed', overflow: 'hidden', position: 'relative' }}>
      <div className="no-scrollbar" style={{ height: '100%', overflowY: 'auto' }}>
        {activeTab === 'chats' && renderChats()}
        {activeTab === 'contacts' && renderContacts()}
        {activeTab === 'discover' && renderDiscover()}
        {activeTab === 'profile' && renderProfile()}
      </div>
      <TabBar active={activeTab} onTabChange={setActiveTab} unread={totalUnread} />
      {activeChat && (
        <ChatPage user={activeChat} messages={messages[activeChat.id] || []} onBack={() => setActiveChat(null)} onSend={handleSendMessage} />
      )}
      {page === 'moments' && <MomentsPage onBack={() => setPage(null)} />}
      {page === 'settings' && <SettingsPage onBack={() => setPage(null)} />}
      {page === 'wallet' && <WalletPage onBack={() => setPage(null)} />}
    </div>
  );
}
