import type { Contact } from '../data/mock';

interface Props { contact: Contact; onClick: () => void; }

export default function ContactCell({ contact, onClick }: Props) {
  const isSpecial = contact.type && ['new','group','tag','official'].includes(contact.type);
  const iconMap: Record<string, { bg: string; label: string }> = {
    new: { bg: '#fa9d3b', label: '新' },
    group: { bg: '#57be6a', label: '群' },
    tag: { bg: '#57be6a', label: '#' },
    official: { bg: '#576b95', label: 'V' },
  };
  return (
    <button onClick={onClick} style={{ display: 'flex', alignItems: 'center', padding: '10px 11px', width: '100%', textAlign: 'left', background: '#fff', position: 'relative', border: 'none', cursor: 'pointer', fontSize: 16 }}>
      <div style={{ flexShrink: 0, borderRadius: 4, overflow: 'hidden', width: 36, height: 36 }}>
        {isSpecial ? (
          <div style={{ width: 36, height: 36, borderRadius: 4, background: iconMap[contact.type!]?.bg || '#ccc', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14, color: '#fff', fontWeight: 700 }}>{iconMap[contact.type!]?.label}</div>
        ) : (
          <img src={contact.avatar} alt={contact.name} style={{ width: 36, height: 36, display: 'block' }} />
        )}
      </div>
      <span style={{ marginLeft: 11, fontSize: 16, color: '#111', flex: 1 }}>{contact.name}</span>
      <svg width="8" height="13" viewBox="0 0 8 13" fill="none"><path d="M1 1l5.5 5.5L1 12" stroke="#c7c7cc" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/></svg>
    </button>
  );
}
