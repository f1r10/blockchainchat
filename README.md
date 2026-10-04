# 🛡️ BlockchainChat — Tam Mərkəzsiz Anonim P2P Şəbəkə

Bu sistem **Signal şifrələməsi**, **Nym mixnet anonimliyi** və **Minimal Blockchain Discovery** prinsipləri üzərində qurulub.

### Əsas Təhlükəsizlik Zəmanətləri:
1. **Heç bir tək serverə bağlılıq yoxdur:** 10-15 maşından ibarət şəbəkədə hər maşın müstəqil rola malikdir.
2. **Blind Mailbox Tokens (Variant B):** Bob-un mailbox tokenləri açıq göndərilmir. Hər iki tərəf KDF ilə deterministik blind token törədir. Mailbox serverləri kimin kimlə yazışdığını bilmir.
3. **3-of-5 Erasure Dağıtımı:** Hər şifrələnmiş paket 5 müstəqil maşındakı Mailbox-lara paylanır. 1 və ya 2 maşın çöksə belə, mesaj itmir (3 pay kifayətdir).
4. **Mixnet Relay Yönləndirməsi:** Paketlər 50-400ms təsadüfi gecikmə ilə hop-hop ötürülür və sabit 4096 bayt ölçüyə salınır (trafik analizi və vaxt korrelyasiyasının qarşısı alınır).
5. **On-Chain Liveness (Variant B):** Blockchain lazımsız heartbeat tx-ləri ilə yüklənmir. Node-lar sadəcə qeydiyyatdan keçir, aktivlik isə tətbiq tərəfindən yerində `/health` ilə yoxlanılır.

---

## 🚀 10–15 Maşında və Telefonlarda Test Bələdçisi

### 1️⃣ Maşın 1 — Blockchain Node (Başlanğıc Nöqtəsi)
Bu maşının IP ünvanı (məs: `192.168.1.101`) hamı tərəfindən bilinir.
```powershell
.\scripts\deploy.ps1 -Role blockchain
```
*Çıxışda sizə kontrakt ünvanı veriləcək (məsələn: `0x5FbDB2315678afecb367f032d93F642f64180aa3`).*

---

### 2️⃣ Maşın 2, 3, 4 — Mix/Relay Node-lar
Bu maşınlar anonim paket qarışdırıcılarıdır:
```powershell
# Maşın 2:
.\scripts\deploy.ps1 -Role relay -BlockchainRpc "http://192.168.1.101:8545" -ContractAddress "0x5FbDB2315678afecb367f032d93F642f64180aa3"

# Maşın 3 və 4-də də eyni qaydada işə salınır.
```

---

### 3️⃣ Maşın 5, 6, 7, 8, 9 — 3-of-5 Mailbox Node-lar
Bu maşınlar şifrəli payları saxlayan müstəqil anbarlardır:
```powershell
# Maşın 5:
.\scripts\deploy.ps1 -Role mailbox -BlockchainRpc "http://192.168.1.101:8545" -ContractAddress "0x5FbDB2315678afecb367f032d93F642f64180aa3"

# Maşın 6, 7, 8, 9-da da eyni qaydada işə salınır.
```

---

### 4️⃣ Maşın 10 — Flutter Web Host (Kompüterlərdən qoşulmaq üçün)
```powershell
.\scripts\deploy.ps1 -Role web -BlockchainRpc "http://192.168.1.101:8545" -ContractAddress "0x5FbDB2315678afecb367f032d93F642f64180aa3"
```
Digər kompüterlərdən brauzerdə `http://192.168.1.110` açaraq istifadə edilir.

---

### 5️⃣ Mobil Telefonlar üçün APK Build
```powershell
.\scripts\deploy.ps1 -Role apk -BlockchainRpc "http://192.168.1.101:8545" -ContractAddress "0x5FbDB2315678afecb367f032d93F642f64180aa3"
```
Yaranan `BlockchainChat.apk` faylını telefonlara ötürüb quraşdırın. Telefonlar eyni Wi-Fi şəbəkəsində olduqda birbaşa bu mərkəzsiz klasterə qoşulacaqlar!

---

## 🧪 Test Ssenariləri (Nəyi Yoxlamalısınız?)

1. **Normal Çat:** Alice `alice` adıyla qeydiyyatdan keçir, Bob `bob` adıyla. Alice Bob-a mesaj yazır. Mesajın 5 payı Relay-lər üzərindən 5 ayrı Mailbox maşınına düşür, Bob dərhal alır.
2. **2 Mailbox-u Söndürün (Fault Tolerance Testi):**
   - Mailbox 1 və Mailbox 2 olan kompüterləri söndürün və ya terminalı bağlayın.
   - Alice yenə Bob-a mesaj yazsın.
   - Bob qalan 3 Mailbox-dan payları toplayıb mesajı bərpa edəcək! (`(3/5 shares)` indikatoru görünəcək).
3. **1 Relay-i Söndürün:**
   - Trafik avtomatik olaraq digər sağlam Relay-lərə yönələcək.
