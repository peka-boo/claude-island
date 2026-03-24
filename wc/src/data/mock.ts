export interface ChatUser {
  id: string; name: string; avatar: string;
  lastMessage: string; time: string; unread: number;
  pinned?: boolean; muted?: boolean; isGroup?: boolean;
}
export interface Message {
  id: string; chatId: string;
  type: 'text' | 'image' | 'voice' | 'video' | 'system' | 'redpacket' | 'location' | 'file' | 'emoji';
  content: string; sender: 'me' | 'other'; time: string;
  senderName?: string; senderAvatar?: string;
  fileName?: string; fileSize?: string;
}
export interface Contact {
  id: string; name: string; avatar: string; letter: string;
  type?: 'new' | 'group' | 'tag' | 'official' | 'service';
  signature?: string;
}
export interface UserProfile {
  id: string; name: string; avatar: string;
  wxid: string; region: string; signature: string;
}

const avatarColors = [
  '#e74c3c','#3498db','#2ecc71','#f39c12','#9b59b6',
  '#1abc9c','#e67e22','#e84393','#00b894','#6c5ce7',
  '#fd79a8','#00cec9','#fab1a0','#55efc4','#74b9ff','#a29bfe',
];

function genAvatar(name: string, size = 100): string {
  const canvas = document.createElement('canvas');
  canvas.width = size; canvas.height = size;
  const ctx = canvas.getContext('2d')!;
  ctx.fillStyle = avatarColors[name.charCodeAt(0) % avatarColors.length];
  ctx.fillRect(0, 0, size, size);
  ctx.fillStyle = '#fff';
  ctx.font = `bold ${size * 0.42}px -apple-system, "PingFang SC", sans-serif`;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  ctx.fillText(name.length > 2 ? name.slice(0, 2) : name, size / 2, size / 2 + 2);
  return canvas.toDataURL('image/jpeg', 0.85);
}
export interface Moment {
  id: string; userId: string; userName: string; avatar: string;
  content: string; images?: string[]; time: string; location?: string;
  likes: string[]; comments: { user: string; text: string }[];
}

export const emojiCodes = [
  '[微笑]','[撇嘴]','[色]','[发呆]','[得意]','[流泪]','[害羞]','[闭嘴]',
  '[睡]','[大哭]','[尴尬]','[发怒]','[调皮]','[呲牙]','[惊讶]','[难过]',
  '[囧]','[抓狂]','[吐]','[偷笑]','[愉快]','[白眼]','[傲慢]','[困]',
  '[惊恐]','[流汗]','[憨笑]','[悠闲]','[奋斗]','[咒骂]','[疑问]','[嘘]',
  '[晕]','[衰]','[骷髅]','[敲打]','[再见]','[擦汗]','[抠鼻]','[鼓掌]',
  '[糗大了]','[坏笑]','[左哼哼]','[右哼哼]','[哈欠]','[鄙视]','[委屈]','[快哭了]',
  '[阴险]','[亲亲]','[可怜]','[菜刀]','[西瓜]','[啤酒]','[咖啡]','[猪头]',
  '[玫瑰]','[凋谢]','[嘴唇]','[爱心]','[心碎]','[蛋糕]','[炸弹]','[便便]',
  '[月亮]','[太阳]','[拥抱]','[强]','[弱]','[握手]','[胜利]','[抱拳]',
  '[勾引]','[拳头]','[OK]','[跳跳]','[发抖]','[怄火]','[转圈]','[磕头]',
  '[回头]','[跳绳]','[挥手]','[嘿哈]','[捂脸]','[奸笑]','[机智]','[皱眉]',
  '[耶]','[蜡烛]','[红包]','[福]','[發]','[让我看看]','[社会社会]','[裂开]',
];

export const currentUser: UserProfile = {
  id: 'me', name: '微信用户', avatar: '',
  wxid: 'wxid_demo123', region: '广东 深圳', signature: '生活不止眼前的苟且',
};

export const chatUsers: ChatUser[] = [
  { id:'1', name:'文件传输助手', avatar:'', lastMessage:'[文件] 项目文档.pdf', time:'14:32', unread:0, pinned:true },
  { id:'2', name:'李维嘉', avatar:'', lastMessage:'[流泪]', time:'13:45', unread:2 },
  { id:'3', name:'公司群', avatar:'', lastMessage:'[权建卓] 大家注意了', time:'12:20', unread:15, isGroup:true },
  { id:'4', name:'权建卓', avatar:'', lastMessage:'哈哈哈太搞笑了', time:'昨天', unread:0 },
  { id:'5', name:'美团外卖', avatar:'', lastMessage:'您的订单已送达，请及时取餐', time:'昨天', unread:1 },
  { id:'6', name:'卢帆新', avatar:'', lastMessage:'[图片]', time:'星期一', unread:0 },
  { id:'7', name:'大学同学群', avatar:'', lastMessage:'[朱智新] 聚会的照片我发群里了', time:'星期日', unread:0, isGroup:true },
  { id:'8', name:'羊种草', avatar:'', lastMessage:'周末一起吃饭吗？', time:'3月15日', unread:0 },
  { id:'9', name:'微信运动', avatar:'', lastMessage:'恭喜！你今天走了8000步', time:'3月15日', unread:0 },
  { id:'10', name:'一只小羊耶', avatar:'', lastMessage:'那个项目进展怎么样了', time:'3月14日', unread:0 },
  { id:'11', name:'前端技术交流群', avatar:'', lastMessage:'[叶彤小哥哥] React 19的新特性', time:'3月14日', unread:0, isGroup:true },
  { id:'12', name:'如心小仙女', avatar:'', lastMessage:'明天有空吗，想约你聊聊', time:'3月13日', unread:0 },
  { id:'13', name:'真页山人', avatar:'', lastMessage:'好的收到', time:'3月12日', unread:0 },
  { id:'14', name:'长安雪花', avatar:'', lastMessage:'明天见', time:'3月12日', unread:0 },
  { id:'15', name:'快递小哥', avatar:'', lastMessage:'您的快递已放前台', time:'3月11日', unread:0 },
  { id:'16', name:'鲜花绿植老板娘', avatar:'', lastMessage:'新到了一批多肉，来看看吧', time:'3月10日', unread:0 },
  { id:'17', name:'施工员小李', avatar:'', lastMessage:'图纸已经发你邮箱了', time:'3月9日', unread:0 },
  { id:'18', name:'樱木.', avatar:'', lastMessage:'下周的比赛加油！', time:'3月8日', unread:0 },
  { id:'19', name:'冰镇西瓜', avatar:'', lastMessage:'天气热了，注意防暑', time:'3月7日', unread:0 },
  { id:'20', name:'董大官人', avatar:'', lastMessage:'那件事情搞定了', time:'3月6日', unread:0 },
];

export const mockMessages: Record<string, Message[]> = {
  '2': [
    { id:'m1', chatId:'2', type:'text', content:'在吗？', sender:'other', time:'13:30', senderName:'李维嘉', senderAvatar:'' },
    { id:'m2', chatId:'2', type:'text', content:'在的，怎么了？', sender:'me', time:'13:31' },
    { id:'m3', chatId:'2', type:'text', content:'明天下午有时间吗？想找你聊聊那个新项目的事', sender:'other', time:'13:35', senderName:'李维嘉', senderAvatar:'' },
    { id:'m4', chatId:'2', type:'text', content:'明天下午2点可以吗？', sender:'me', time:'13:40' },
    { id:'m5', chatId:'2', type:'text', content:'可以的，在老地方？', sender:'other', time:'13:42', senderName:'李维嘉', senderAvatar:'' },
    { id:'m6', chatId:'2', type:'emoji', content:'[流泪]', sender:'other', time:'13:45', senderName:'李维嘉', senderAvatar:'' },
  ],
  '1': [
    { id:'m10', chatId:'1', type:'text', content:'发个文件到电脑', sender:'me', time:'14:20' },
    { id:'m11', chatId:'1', type:'file', content:'项目文档.pdf', sender:'me', time:'14:32', fileName:'项目文档.pdf', fileSize:'2.3MB' },
  ],
  '3': [
    { id:'m20', chatId:'3', type:'text', content:'大家注意了', sender:'other', time:'12:20', senderName:'权建卓', senderAvatar:'' },
  ],
  '4': [
    { id:'m30', chatId:'4', type:'text', content:'你看这个视频了吗', sender:'other', time:'昨天', senderName:'权建卓', senderAvatar:'' },
    { id:'m31', chatId:'4', type:'text', content:'没有，发给我看看', sender:'me', time:'昨天' },
    { id:'m32', chatId:'4', type:'text', content:'哈哈哈太搞笑了', sender:'other', time:'昨天', senderName:'权建卓', senderAvatar:'' },
  ],
  '5': [
    { id:'m40', chatId:'5', type:'text', content:'您的订单已送达，请及时取餐', sender:'other', time:'昨天', senderName:'美团外卖', senderAvatar:'' },
  ],
  '10': [
    { id:'m60', chatId:'10', type:'text', content:'那个项目进展怎么样了', sender:'other', time:'3月14日', senderName:'一只小羊耶', senderAvatar:'' },
    { id:'m61', chatId:'10', type:'text', content:'还在开发中，下周应该能出第一个版本', sender:'me', time:'3月14日' },
    { id:'m62', chatId:'10', type:'text', content:'好的，辛苦了！', sender:'other', time:'3月14日', senderName:'一只小羊耶', senderAvatar:'' },
  ],
};

export const contacts: Contact[] = [
  { id:'new', name:'新的朋友', avatar:'', letter:'', type:'new' },
  { id:'group', name:'群聊', avatar:'', letter:'', type:'group' },
  { id:'tag', name:'标签', avatar:'', letter:'', type:'tag' },
  { id:'official', name:'公众号', avatar:'', letter:'', type:'official' },
  { id:'c1', name:'陈可欣', avatar:'', letter:'C' },
  { id:'c2', name:'程雪', avatar:'', letter:'C' },
  { id:'d1', name:'丁一', avatar:'', letter:'D' },
  { id:'l1', name:'李维嘉', avatar:'', letter:'L' },
  { id:'l2', name:'刘洋', avatar:'', letter:'L' },
  { id:'l3', name:'卢帆新', avatar:'', letter:'L' },
  { id:'w1', name:'王建华', avatar:'', letter:'W' },
  { id:'w2', name:'吴世伟', avatar:'', letter:'W' },
  { id:'y1', name:'羊种草', avatar:'', letter:'Y' },
  { id:'y2', name:'一只小羊耶', avatar:'', letter:'Y' },
  { id:'y3', name:'叶彤小哥哥', avatar:'', letter:'Y' },
  { id:'z1', name:'张乙豪', avatar:'', letter:'Z' },
  { id:'z2', name:'赵六', avatar:'', letter:'Z' },
  { id:'z3', name:'周八', avatar:'', letter:'Z' },
  { id:'z4', name:'朱智新', avatar:'', letter:'Z' },
  { id:'q1', name:'权建卓', avatar:'', letter:'Q' },
];

export const discoverItems = [
  { id:'moments', label:'朋友圈', badge:3, iconSvg: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-1 17.93c-3.95-.49-7-3.85-7-7.93 0-.62.08-1.21.21-1.79L9 15v1c0 1.1.9 2 2 2v1.93zm6.9-2.54c-.26-.81-1-1.39-1.9-1.39h-1v-3c0-.55-.45-1-1-1H8v-2h2c.55 0 1-.45 1-1V7h2c1.1 0 2-.9 2-2v-.41c2.93 1.19 5 4.06 5 7.41 0 2.08-.8 3.97-2.1 5.39z"/>' },
  { id:'scan', label:'扫一扫', iconSvg: '<path d="M9.5 6.5v3h-3v-3h3M11 5H5v6h6V5zm-1.5 9.5v3h-3v-3h3M11 13H5v6h6v-6zm6.5-6.5v3h-3v-3h3M19 5h-6v6h6V5zm-6 8h1.5v1.5H13V13zm1.5 1.5H16V16h-1.5v-1.5zM16 13h1.5v1.5H16V13zm-3 3h1.5v1.5H13V16zm1.5 1.5H16V19h-1.5v-1.5zM16 16h1.5v1.5H16V16zm1.5-1.5H19V16h-1.5v-1.5zm0 3H19V19h-1.5v-1.5z"/>' },
  { id:'shake', label:'摇一摇', iconSvg: '<path d="M2 12l1.41 1.41L7 9.83V22h2V9.83l3.59 3.58L14 12l-6-6-6 6zm18-6l-1.41-1.41L15 8.17V-2h-2v10.17l-3.59-3.58L8 6l6 6 6-6z"/>' },
  { id:'search', label:'看一看', iconSvg: '<path d="M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"/>' },
  { id:'nearby', label:'搜一搜', iconSvg: '<path d="M15.5 14h-.79l-.28-.27C15.41 12.59 16 11.11 16 9.5 16 5.91 13.09 3 9.5 3S3 5.91 3 9.5 5.91 16 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z"/>' },
  { id:'shop', label:'购物', divider:true, iconSvg: '<path d="M7 18c-1.1 0-1.99.9-1.99 2S5.9 22 7 22s2-.9 2-2-.9-2-2-2zM1 2v2h2l3.6 7.59-1.35 2.45c-.16.28-.25.61-.25.96 0 1.1.9 2 2 2h12v-2H7.42c-.14 0-.25-.11-.25-.25l.03-.12.9-1.63h7.45c.75 0 1.41-.41 1.75-1.03l3.58-6.49c.08-.14.12-.31.12-.48 0-.55-.45-1-1-1H5.21l-.94-2H1zm16 16c-1.1 0-1.99.9-1.99 2s.89 2 1.99 2 2-.9 2-2-.9-2-2-2z"/>' },
  { id:'game', label:'游戏', iconSvg: '<path d="M21.58 16.09l-1.09-7.66C20.21 6.46 18.52 5 16.53 5H7.47C5.48 5 3.79 6.46 3.51 8.43l-1.09 7.66C2.2 17.63 3.39 19 4.94 19h0c.68 0 1.32-.27 1.8-.75L9 16h6l2.25 2.25c.48.48 1.13.75 1.8.75h0c1.56 0 2.75-1.37 2.53-2.91zM11 11H9v2H8v-2H6v-1h2V8h1v2h2v1zm4 2c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1zm2-3c-.55 0-1-.45-1-1s.45-1 1-1 1 .45 1 1-.45 1-1 1z"/>' },
  { id:'mini', label:'小程序', divider:true, iconSvg: '<path d="M3 11h8V3H3v8zm2-6h4v4H5V5zm8-2v8h8V3h-8zm6 6h-4V5h4v4zM3 21h8v-8H3v8zm2-6h4v4H5v-4zm13-2h-2v3h-3v2h3v3h2v-3h3v-2h-3v-3z"/>' },
];

export const profileItems = [
  { id:'pay', label:'支付', divider:true, iconSvg: '<path d="M20 4H4c-1.11 0-1.99.89-1.99 2L2 18c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V6c0-1.11-.89-2-2-2zm0 14H4v-6h16v6zm0-10H4V6h16v2z"/>' },
  { id:'favorites', label:'收藏', iconSvg: '<path d="M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z"/>' },
  { id:'album', label:'相册', iconSvg: '<path d="M21 19V5c0-1.1-.9-2-2-2H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2zM8.5 13.5l2.5 3.01L14.5 12l4.5 6H5l3.5-4.5z"/>' },
  { id:'cards', label:'卡包', iconSvg: '<path d="M20 6H4c-1.11 0-2 .89-2 2v8c0 1.11.89 2 2 2h16c1.11 0 2-.89 2-2V8c0-1.11-.89-2-2-2zm0 2v.01H4V8h16zm-8 6H4v-2h8v2zm6 0h-4v-2h4v2zm4-4H4V8h18v2z"/>' },
  { id:'emoji', label:'表情', divider:true, iconSvg: '<path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-4-8c.79 0 1.5-.71 1.5-1.5S8.79 9 8 9s-1.5.71-1.5 1.5S7.21 12 8 12zm8 0c.79 0 1.5-.71 1.5-1.5S16.79 9 16 9s-1.5.71-1.5 1.5.71 1.5 1.5 1.5zm-4 4c2.21 0 4-1.79 4-4h-8c0 2.21 1.79 4 4 4z"/>' },
  { id:'settings', label:'设置', iconSvg: '<path d="M19.14 12.94c.04-.3.06-.61.06-.94 0-.32-.02-.64-.07-.94l2.03-1.58c.18-.14.23-.41.12-.61l-1.92-3.32c-.12-.22-.37-.29-.59-.22l-2.39.96c-.5-.38-1.03-.7-1.62-.94l-.36-2.54c-.04-.24-.24-.41-.48-.41h-3.84c-.24 0-.43.17-.47.41l-.36 2.54c-.59.24-1.13.57-1.62.94l-2.39-.96c-.22-.08-.47 0-.59.22L2.74 8.87c-.12.21-.08.47.12.61l2.03 1.58c-.05.3-.07.62-.07.94s.02.64.07.94l-2.03 1.58c-.18.14-.23.41-.12.61l1.92 3.32c.12.22.37.29.59.22l2.39-.96c.5.38 1.03.7 1.62.94l.36 2.54c.05.24.24.41.48.41h3.84c.24 0 .44-.17.47-.41l.36-2.54c.59-.24 1.13-.56 1.62-.94l2.39.96c.22.08.47 0 .59-.22l1.92-3.32c.12-.22.07-.47-.12-.61l-2.01-1.58zM12 15.6c-1.98 0-3.6-1.62-3.6-3.6s1.62-3.6 3.6-3.6 3.6 1.62 3.6 3.6-1.62 3.6-3.6 3.6z"/>' },
];

export const momentsData: Moment[] = [
  {
    id:'mom1', userId:'2', userName:'李维嘉', avatar:'',
    content:'今天天气真好，出去走走 ☀️', images:[], time:'3小时前', location:'广东 深圳',
    likes:['权建卓','卢帆新'], comments:[{user:'权建卓',text:'真羡慕！'}],
  },
  {
    id:'mom2', userId:'4', userName:'权建卓', avatar:'',
    content:'新项目终于上线了，感谢团队的每一位小伙伴！🎉', images:[], time:'5小时前',
    likes:['李维嘉','一只小羊耶','羊种草'], comments:[{user:'李维嘉',text:'恭喜恭喜！'},{user:'一只小羊耶',text:'厉害了！'}],
  },
  {
    id:'mom3', userId:'10', userName:'一只小羊耶', avatar:'',
    content:'今天的咖啡不错 ☕ 在南山区的一家小店里发现的宝藏咖啡馆', images:[], time:'昨天', location:'深圳 南山',
    likes:['如心小仙女'], comments:[],
  },
  {
    id:'mom4', userId:'12', userName:'如心小仙女', avatar:'',
    content:'春天来了，花都开了 🌸🌺🌷', images:[], time:'昨天',
    likes:['李维嘉','权建卓','羊种草','一只小羊耶'], comments:[{user:'羊种草',text:'好美啊！'}],
  },
  {
    id:'mom5', userId:'8', userName:'羊种草', avatar:'',
    content:'周末和朋友们一起去爬山，风景太美了！', images:[], time:'2天前', location:'深圳 梧桐山',
    likes:['李维嘉'], comments:[{user:'李维嘉',text:'下次叫我一起！'}],
  },
];

export function initAvatars() {
  currentUser.avatar = genAvatar(currentUser.name);
  chatUsers.forEach(u => { u.avatar = genAvatar(u.name); });
  contacts.forEach(c => { c.avatar = genAvatar(c.name); });
  momentsData.forEach(m => { m.avatar = genAvatar(m.userName); });
  Object.values(mockMessages).forEach(msgs => {
    msgs.forEach(m => {
      if (m.senderName && m.senderAvatar !== undefined) {
        m.senderAvatar = genAvatar(m.senderName);
      }
    });
  });
}
