# ระบบออกใบเสร็จรับเงิน RUS

เว็บระบบออกใบเสร็จรับเงินสำหรับมหาวิทยาลัยเทคโนโลยีราชมงคลสุวรรณภูมิ ใช้งานผ่าน GitHub Pages ได้โดยตรง

## Login

### Admin

```text
Username: admin
Password: 9999
```

Admin ไม่ต้องกรอกอีเมล

### User

User กรอกรหัส 4 หลักที่ Admin สร้างในหน้า Admin

## ไฟล์สำคัญ

- `index.html` หน้าเว็บหลัก
- `supabase-config.js` ไฟล์ใส่ค่าเชื่อมต่อ Supabase
- `schema.sql` SQL สำหรับสร้างฐานข้อมูลกลาง
- `SUPABASE_SETUP.md` คู่มือตั้งค่า Supabase
- `.nojekyll` สำหรับ GitHub Pages

## โหมดการใช้งาน

### 1. โหมดทดลองในเครื่อง

ถ้ายังไม่ใส่ค่า Supabase ใน `supabase-config.js` ข้อมูลจะเก็บใน Browser ด้วย `localStorage`

เหมาะสำหรับทดลอง แต่ข้อมูลจะไม่แชร์ข้ามเครื่อง

### 2. โหมดฐานข้อมูลกลาง Supabase

เมื่อใส่ `Project URL` และ `anon public key` ใน `supabase-config.js` ระบบจะใช้ Supabase เป็นฐานข้อมูลกลาง

ความสามารถหลัก:

- ใช้ได้หลายเครื่อง
- ข้อมูลอัปเดตผ่าน Realtime
- Admin สร้าง User รหัส 4 หลัก
- User ใช้รหัส 4 หลักเพื่อออกใบเสร็จ
- การออกเลขใบเสร็จทำผ่าน SQL function `issue_receipt` และล็อกแถว `app_state` ด้วย `for update` เพื่อช่วยกันเลขซ้ำเมื่อหลายคนออกพร้อมกัน
- ยกเลิกใบเสร็จพร้อมบันทึกหมายเหตุ

## วิธีเปิดใช้งาน GitHub Pages

1. เข้า Repository นี้ใน GitHub
2. ไปที่ `Settings`
3. เลือก `Pages`
4. ที่ `Build and deployment` เลือก `Deploy from a branch`
5. เลือก branch `main` และ folder `/root`
6. กด `Save`
7. รอประมาณ 1-3 นาที แล้วเปิด URL ที่ GitHub Pages แสดง

## วิธีตั้งค่า Supabase

อ่านคู่มือใน `SUPABASE_SETUP.md`

สรุปขั้นตอน:

1. สร้าง Supabase Project
2. เปิด `SQL Editor`
3. คัดลอก SQL จาก `schema.sql` ไป Run
4. เปิด `Project Settings > API`
5. คัดลอก `Project URL` และ `anon public key`
6. ใส่ค่าใน `supabase-config.js`
7. Commit/Push ขึ้น GitHub

## ข้อควรระวัง

- ห้ามใส่ `service_role key` ลงใน `supabase-config.js`
- `anon public key` ใช้ในเว็บได้ตามปกติ
- โหมด LocalStorage ไม่เหมาะกับใช้งานจริงหลายเครื่อง
- ก่อนใช้งานจริงควรทดสอบออกใบเสร็จพร้อมกันหลายเครื่อง และตรวจรายงานเลขใบเสร็จ
