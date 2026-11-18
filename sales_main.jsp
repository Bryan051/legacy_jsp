<%--
================================================================================
  sales_main.jsp
  SMS 영업관리시스템 - 거래처 · 영업기회 · 견적 · 수주 · 계약 · 청구 · 수금 · 리포트 통합 화면
  (Tomcat 8 / JDK 1.8 / MySQL 5.5 ~ 5.7)

  화면과 처리가 전부 이 파일 하나에 있다.  주소는 항상 sales_main.jsp?cmd=<명령> 형식이고
  cmd 를 안 주면 main(대시보드).  새 화면은 아래 if ~ else if 분기에 추가할 것.
  (처리 전용 cmd = 위쪽 분기 / 화면 cmd = 아래쪽 분기)

  변경 이력
  2016.03.07  홍길동  최초 작성 (사원 · 거래처 · 제품 · 견적 · 수주)
  2016.09.05  김철수  계약 · 청구 추가
  2017.03.13  홍길동  수금 · 미수 현황 추가
  2017.08.30  김철수  금액 서식 메서드(fmtAmt) 추가
  2019.08.22  홍길동  여신 관리(TB_CUSTOMER.CREDIT_STATUS) 추가, 공통코드 application 캐시
  2019.11.05  김철수  전자세금계산서 발행 연동 · 수주 완료 처리 추가 (고객 요청으로 급히)
  2020.02.10  김철수  제품 기간별 단가(TB_PRODUCT_PRICE) 적용
  2021.03.15  김철수  매출 리포트 · 월마감(CLOSE_YN) 추가
  2022.05.30  홍길동  미수 안내 메일 · 월마감 배치 cmd 추가 (cron 에서 wget 으로 호출)
  2023.01.17  김철수  배치 호출용 key 파라미터 추가 (로그인 없이 부르려고)

  설치 메모
  1) MySQL 5.5 이상, InnoDB, utf8.  아래 DDL 을 sms 스키마에 실행한다.
  2) Tomcat context.xml 에 jdbc/smsDS (DataSource) 등록.  없으면 선언부의 DB_URL 로 직접 연결한다.
  3) 계약서 첨부 저장 폴더 /data/sms/upload 를 만들어 두고 Tomcat 계정에 쓰기 권한을 준다.
  4) 배치는 cron 에서 호출한다.
       30 1 1 * *      wget -q -O - "http://localhost:8080/sms/sales_main.jsp?cmd=batchClose&key=배치키"
       0  9 * * 1-5    wget -q -O - "http://localhost:8080/sms/sales_main.jsp?cmd=batchArrears&key=배치키"
       0  2 1 * *      wget -q -O - "http://localhost:8080/sms/sales_main.jsp?cmd=batchAll&key=배치키"     (2023.01 추가. 위 batchClose 는 안 지웠음)
  5) 최초 관리자(ADMIN) 계정은 TB_USER 에 직접 넣는다. 비밀번호는 SHA2(비밀번호, 256) 값.
     TB_AUTH 에는 ADMIN / MANAGER / USER 를, TB_CODE 에는 CUST_GRADE · CREDIT_STATUS · COLLECT_METHOD 그룹을 먼저 넣어 둔다.
  6) 공통코드를 고친 뒤에는 화면의 [캐시 갱신] 을 눌러야 바로 반영된다 (안 눌러도 10분 뒤 반영).

  아래는 테이블 정의 (2022.05 기준)
================================================================================

SET NAMES utf8;

-- 사원 · 부서 · 권한
CREATE TABLE IF NOT EXISTS TB_DEPT (
    DEPT_ID VARCHAR(10) NOT NULL COMMENT '부서ID',
    DEPT_NM VARCHAR(50) NOT NULL COMMENT '부서명',
    PARENT_DEPT_ID VARCHAR(10) NULL COMMENT '상위부서ID',
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y' COMMENT '사용여부',
    REG_DT DATETIME NOT NULL COMMENT '등록일시',
    PRIMARY KEY (DEPT_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='부서';

CREATE TABLE IF NOT EXISTS TB_AUTH (
    AUTH_CD VARCHAR(10) NOT NULL COMMENT '권한코드',
    AUTH_NM VARCHAR(30) NOT NULL COMMENT '권한명',
    AUTH_DESC VARCHAR(200) NULL COMMENT '설명',
    PRIMARY KEY (AUTH_CD)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='권한';

CREATE TABLE IF NOT EXISTS TB_USER (
    USER_ID VARCHAR(20) NOT NULL COMMENT '사원ID',
    USER_NM VARCHAR(30) NOT NULL COMMENT '사원명',
    PASSWD VARCHAR(100) NOT NULL COMMENT '비밀번호(SHA2 해시)',
    DEPT_ID VARCHAR(10) NULL COMMENT '부서ID',
    AUTH_CD VARCHAR(10) NOT NULL DEFAULT 'USER' COMMENT '권한코드',
    EMAIL VARCHAR(100) NULL,
    TEL_NO VARCHAR(20) NULL,
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y',
    LAST_LOGIN_DT DATETIME NULL,
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (USER_ID),
    KEY IDX_USER_DEPT (DEPT_ID),
    CONSTRAINT FK_USER_DEPT FOREIGN KEY (DEPT_ID) REFERENCES TB_DEPT (DEPT_ID)
    -- AUTH_CD 는 FK 없음 (권한 코드가 자주 바뀌어서)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='사원';

-- 거래처
CREATE TABLE IF NOT EXISTS TB_CUSTOMER (
    CUST_ID VARCHAR(20) NOT NULL COMMENT '거래처ID',
    CUST_NM VARCHAR(100) NOT NULL COMMENT '거래처명',
    BIZ_NO VARCHAR(12) NULL COMMENT '사업자등록번호',
    CEO_NM VARCHAR(30) NULL COMMENT '대표자명',
    ADDR VARCHAR(200) NULL COMMENT '주소',
    ADDR_DTL VARCHAR(100) NULL COMMENT '상세주소',
    TEL_NO VARCHAR(20) NULL,
    CUST_GRADE CHAR(1) NOT NULL DEFAULT 'C' COMMENT '거래처등급 A/B/C',
    CREDIT_STATUS VARCHAR(2) NOT NULL DEFAULT '01' COMMENT '여신상태 01정상 02미수 03연체',
    CREDIT_LIMIT DECIMAL(15,0) NULL COMMENT '여신한도',
    CHARGE_USER_ID VARCHAR(20) NULL COMMENT '담당사원',
    LAST_NOTICE_DT DATETIME NULL COMMENT '마지막 미수안내 발송일시',
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y',
    REG_USER_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (CUST_ID),
    KEY IDX_CUSTOMER_NM (CUST_NM),
    KEY IDX_CUSTOMER_BIZ (BIZ_NO),
    CONSTRAINT FK_CUSTOMER_USER FOREIGN KEY (CHARGE_USER_ID) REFERENCES TB_USER (USER_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='거래처';

CREATE TABLE IF NOT EXISTS TB_CUST_CONTACT (
    CONTACT_ID BIGINT NOT NULL AUTO_INCREMENT,
    CUST_ID VARCHAR(20) NOT NULL,
    CONTACT_NM VARCHAR(30) NOT NULL COMMENT '담당자명',
    DEPT_NM VARCHAR(50) NULL,
    POSITION_NM VARCHAR(30) NULL COMMENT '직위',
    EMAIL VARCHAR(100) NULL,
    MOBILE_NO VARCHAR(20) NULL,
    MAIN_YN CHAR(1) NOT NULL DEFAULT 'N' COMMENT '대표담당자 여부',
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (CONTACT_ID),
    KEY IDX_CONTACT_CUST (CUST_ID),
    CONSTRAINT FK_CONTACT_CUST FOREIGN KEY (CUST_ID) REFERENCES TB_CUSTOMER (CUST_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='거래처 담당자';

-- 제품 · 단가
CREATE TABLE IF NOT EXISTS TB_PRODUCT (
    PRODUCT_ID VARCHAR(20) NOT NULL COMMENT '제품ID',
    PRODUCT_NM VARCHAR(100) NOT NULL COMMENT '제품명',
    PRODUCT_TYPE VARCHAR(10) NULL COMMENT '제품유형',
    UNIT_CD VARCHAR(5) NULL COMMENT '단위',
    UNIT_PRICE DECIMAL(15,0) NOT NULL DEFAULT 0 COMMENT '기본단가',
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y',
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (PRODUCT_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='제품';

CREATE TABLE IF NOT EXISTS TB_PRODUCT_PRICE (
    PRICE_ID BIGINT NOT NULL AUTO_INCREMENT,
    PRODUCT_ID VARCHAR(20) NOT NULL,
    CUST_GRADE CHAR(1) NULL COMMENT '적용 거래처등급(없으면 공통)',
    UNIT_PRICE DECIMAL(15,0) NOT NULL,
    APPLY_FROM_DT DATE NOT NULL,
    APPLY_TO_DT DATE NOT NULL,
    PRIMARY KEY (PRICE_ID),
    KEY IDX_PRICE_PRODUCT (PRODUCT_ID, APPLY_FROM_DT),
    CONSTRAINT FK_PRICE_PRODUCT FOREIGN KEY (PRODUCT_ID) REFERENCES TB_PRODUCT (PRODUCT_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='제품 기간별 단가';

-- 영업기회 · 견적
CREATE TABLE IF NOT EXISTS TB_OPPTY (
    OPPTY_ID VARCHAR(20) NOT NULL COMMENT '영업기회ID',
    CUST_ID VARCHAR(20) NOT NULL,
    OPPTY_NM VARCHAR(100) NOT NULL,
    STAGE_CD VARCHAR(2) NOT NULL DEFAULT '10' COMMENT '10발굴 20제안 30협상 40수주 90실주',
    EXPECT_AMT DECIMAL(15,0) NULL,
    EXPECT_CLOSE_DT DATE NULL,
    CHARGE_USER_ID VARCHAR(20) NULL,
    STATUS_CD VARCHAR(2) NOT NULL DEFAULT '10' COMMENT '10진행 90종결',
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (OPPTY_ID),
    KEY IDX_OPPTY_CUST (CUST_ID)
    -- CUST_ID FK 없음 (2017.02 이관 때 빠짐)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='영업기회';

CREATE TABLE IF NOT EXISTS TB_QUOTE (
    QUOTE_ID VARCHAR(20) NOT NULL COMMENT '견적ID',
    OPPTY_ID VARCHAR(20) NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    QUOTE_NM VARCHAR(100) NULL,
    QUOTE_DT DATE NOT NULL,
    VALID_DT DATE NULL COMMENT '유효기한',
    TOTAL_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    STATUS_CD VARCHAR(2) NOT NULL DEFAULT '10' COMMENT '10작성 20제출 90종결',
    CHARGE_USER_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (QUOTE_ID),
    KEY IDX_QUOTE_CUST (CUST_ID),
    CONSTRAINT FK_QUOTE_CUST FOREIGN KEY (CUST_ID) REFERENCES TB_CUSTOMER (CUST_ID)
    -- OPPTY_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='견적';

CREATE TABLE IF NOT EXISTS TB_QUOTE_ITEM (
    QUOTE_ID VARCHAR(20) NOT NULL,
    ITEM_SEQ INT NOT NULL,
    PRODUCT_ID VARCHAR(20) NOT NULL,
    QTY INT NOT NULL DEFAULT 1,
    UNIT_PRICE DECIMAL(15,0) NOT NULL DEFAULT 0,
    AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (QUOTE_ID, ITEM_SEQ),
    CONSTRAINT FK_QITEM_QUOTE FOREIGN KEY (QUOTE_ID) REFERENCES TB_QUOTE (QUOTE_ID)
    -- PRODUCT_ID FK 없음 (단종 제품이 있어서)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='견적 품목';

-- 수주 · 계약
CREATE TABLE IF NOT EXISTS TB_ORDER (
    ORDER_ID VARCHAR(20) NOT NULL COMMENT '수주ID',
    QUOTE_ID VARCHAR(20) NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    ORDER_DT DATE NOT NULL,
    ORDER_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    ORDER_STATUS VARCHAR(20) NOT NULL DEFAULT '접수' COMMENT '접수/계약완료/청구완료/수금완료/취소',
    CONTRACT_ID VARCHAR(20) NULL,
    CLOSE_YN CHAR(1) NOT NULL DEFAULT 'N' COMMENT '월마감 여부',
    CLOSE_YM CHAR(6) NULL COMMENT '마감년월 YYYYMM',
    CHARGE_USER_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (ORDER_ID),
    KEY IDX_ORDER_CUST (CUST_ID, ORDER_DT),
    KEY IDX_ORDER_STATUS (ORDER_STATUS),
    CONSTRAINT FK_ORDER_CUST FOREIGN KEY (CUST_ID) REFERENCES TB_CUSTOMER (CUST_ID)
    -- QUOTE_ID · CONTRACT_ID FK 없음 (순서 문제로 못 걸었음)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수주';

CREATE TABLE IF NOT EXISTS TB_ORDER_ITEM (
    ORDER_ID VARCHAR(20) NOT NULL,
    ITEM_SEQ INT NOT NULL,
    PRODUCT_ID VARCHAR(20) NOT NULL,
    QTY INT NOT NULL DEFAULT 1,
    UNIT_PRICE DECIMAL(15,0) NOT NULL DEFAULT 0,
    AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (ORDER_ID, ITEM_SEQ),
    KEY IDX_OITEM_PRODUCT (PRODUCT_ID),
    CONSTRAINT FK_OITEM_ORDER FOREIGN KEY (ORDER_ID) REFERENCES TB_ORDER (ORDER_ID)
    -- PRODUCT_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수주 품목';

CREATE TABLE IF NOT EXISTS TB_CONTRACT (
    CONTRACT_ID VARCHAR(20) NOT NULL COMMENT '계약ID',
    ORDER_ID VARCHAR(20) NOT NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    CONTRACT_NM VARCHAR(100) NULL,
    CONTRACT_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    START_DT DATE NULL,
    END_DT DATE NULL,
    STATUS_CD VARCHAR(2) NOT NULL DEFAULT '10' COMMENT '10진행 90종료',
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (CONTRACT_ID),
    KEY IDX_CONTRACT_ORDER (ORDER_ID)
    -- ORDER_ID · CUST_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='계약';

-- 청구 · 수금
CREATE TABLE IF NOT EXISTS TB_BILL (
    BILL_ID VARCHAR(20) NOT NULL COMMENT '청구ID',
    ORDER_ID VARCHAR(20) NOT NULL,
    CONTRACT_ID VARCHAR(20) NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    BILL_DT DATE NOT NULL,
    SUPPLY_AMT DECIMAL(15,0) NOT NULL DEFAULT 0 COMMENT '공급가액',
    TAX_AMT DECIMAL(15,0) NOT NULL DEFAULT 0 COMMENT '세액',
    TOTAL_AMT DECIMAL(15,0) NOT NULL DEFAULT 0 COMMENT '합계',
    ETAX_NO VARCHAR(30) NULL COMMENT '전자세금계산서 승인번호',
    ISSUE_STATUS VARCHAR(2) NOT NULL DEFAULT '00' COMMENT '00대기 10발행 90실패',
    CLOSE_YN CHAR(1) NOT NULL DEFAULT 'N',
    CLOSE_YM CHAR(6) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (BILL_ID),
    KEY IDX_BILL_CUST (CUST_ID, BILL_DT),
    KEY IDX_BILL_ORDER (ORDER_ID),
    CONSTRAINT FK_BILL_CUST FOREIGN KEY (CUST_ID) REFERENCES TB_CUSTOMER (CUST_ID)
    -- ORDER_ID · CONTRACT_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='청구(세금계산서)';

CREATE TABLE IF NOT EXISTS TB_COLLECT (
    COLLECT_ID VARCHAR(20) NOT NULL COMMENT '수금ID',
    BILL_ID VARCHAR(20) NOT NULL,
    ORDER_ID VARCHAR(20) NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    COLLECT_DT DATE NOT NULL,
    COLLECT_AMT DECIMAL(15,0) NOT NULL,
    COLLECT_METHOD VARCHAR(2) NULL COMMENT '01계좌이체 02현금 03어음',
    REG_USER_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (COLLECT_ID),
    KEY IDX_COLLECT_BILL (BILL_ID),
    KEY IDX_COLLECT_CUST (CUST_ID),
    CONSTRAINT FK_COLLECT_BILL FOREIGN KEY (BILL_ID) REFERENCES TB_BILL (BILL_ID)
    -- ORDER_ID · CUST_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수금';

-- 공통코드 · 공지
CREATE TABLE IF NOT EXISTS TB_CODE (
    GRP_CD VARCHAR(20) NOT NULL COMMENT '코드그룹',
    CD VARCHAR(20) NOT NULL COMMENT '코드',
    CD_NM VARCHAR(100) NOT NULL COMMENT '코드명',
    SORT_ORD INT NOT NULL DEFAULT 0,
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y',
    PRIMARY KEY (GRP_CD, CD)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='공통코드';

CREATE TABLE IF NOT EXISTS TB_NOTICE (
    NOTICE_ID BIGINT NOT NULL AUTO_INCREMENT,
    TITLE VARCHAR(200) NOT NULL,
    CONTENT TEXT NULL,
    WRITER_ID VARCHAR(20) NULL,
    VIEW_CNT INT NOT NULL DEFAULT 0,
    TOP_YN CHAR(1) NOT NULL DEFAULT 'N' COMMENT '상단고정',
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (NOTICE_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='공지사항';
--%>
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="java.text.*" %>
<%@ page import="java.io.*" %>
<%@ page import="java.net.*" %>
<%@ page import="javax.naming.*" %>
<%@ page import="javax.sql.*" %>
<%@ page import="java.util.Base64" %>
<%!
    /* ====================================================================
     *  선언부 : 상수 · 공통 메서드
     *  2016.03.07 홍길동 최초 작성 / 이후 필요할 때마다 여러 사람이 추가
     * ==================================================================== */

    // ---- 상수 (운영 반영 전에 DB_PASS 확인할 것)
    private static final String JNDI_NAME  = "java:comp/env/jdbc/smsDS";
    private static final String DB_URL     = "jdbc:mysql://127.0.0.1:3306/sms?useUnicode=true&characterEncoding=utf8";
    private static final String DB_USER    = "smsuser";
    private static final String DB_PASS    = "changeme";
    private static final String ETAX_URL   = "http://etax.example.com/api/issue";   // 연동 업체 제공 주소
    private static final String UPLOAD_DIR = "/data/sms/upload";                    // 계약서 첨부 저장 위치
    private static final String MAIL_HOST  = "mail.example.com";
    private static final String MAIL_FROM  = "sms-noreply@example.com";
    private static final String BATCH_KEY  = "changeme";                            // cron 이 wget 할 때 넘기는 키
    private static final String CODE_CACHE = "SMS_CODE_CACHE";                      // application 속성 이름
    private static final double VAT_RATE   = 0.1;
    private static int idSeq = 0;

    /** 커넥션 : 운영은 JNDI, 개발 PC 는 JNDI 가 없어서 직접 연결 */
    private Connection getConn() throws Exception {
        try {
            DataSource ds = (DataSource) new InitialContext().lookup(JNDI_NAME);
            return ds.getConnection();
        } catch (NamingException ne) {
            Class.forName("com.mysql.jdbc.Driver");
            return DriverManager.getConnection(DB_URL, DB_USER, DB_PASS);
        }
    }

    private void closeAll(ResultSet rs, Statement st, Connection conn) {
        try { if (rs != null) rs.close(); } catch (Exception e) { }
        try { if (st != null) st.close(); } catch (Exception e) { }
        try { if (conn != null) conn.close(); } catch (Exception e) { }
    }

    private void rollbackQuietly(Connection conn) {
        try { if (conn != null) conn.rollback(); } catch (Exception e) { }
    }

    // ---- PreparedStatement 를 감싼 조회 · 변경 (2019.08 이후 화면은 이걸 쓴다. 옛 화면은 직접 JDBC)
    private void bindParams(PreparedStatement ps, Object[] p) throws SQLException {
        if (p == null) return;
        for (int i = 0; i < p.length; i++) {
            ps.setObject(i + 1, p[i]);
        }
    }

    /** SELECT 결과를 HashMap(컬럼명 대문자) 목록으로 */
    private List<HashMap<String, Object>> queryList(Connection conn, String sql, Object[] p) throws SQLException {
        PreparedStatement ps = null;
        ResultSet rs = null;
        List<HashMap<String, Object>> list = new ArrayList<HashMap<String, Object>>();
        try {
            ps = conn.prepareStatement(sql);
            bindParams(ps, p);
            rs = ps.executeQuery();
            ResultSetMetaData md = rs.getMetaData();
            int iCols = md.getColumnCount();
            while (rs.next()) {
                HashMap<String, Object> row = new HashMap<String, Object>();
                for (int i = 1; i <= iCols; i++) {
                    row.put(md.getColumnLabel(i).toUpperCase(), rs.getObject(i));
                }
                list.add(row);
            }
        } finally {
            closeAll(rs, ps, null);
        }
        return list;
    }

    private HashMap<String, Object> queryOne(Connection conn, String sql, Object[] p) throws SQLException {
        List<HashMap<String, Object>> list = queryList(conn, sql, p);
        return list.isEmpty() ? null : list.get(0);
    }

    private long queryLong(Connection conn, String sql, Object[] p, long def) throws SQLException {
        HashMap<String, Object> row = queryOne(conn, sql, p);
        Object v = row == null ? null : row.values().iterator().next();
        return v == null ? def : ((Number) v).longValue();
    }

    private int execUpdate(Connection conn, String sql, Object[] p) throws SQLException {
        PreparedStatement ps = null;
        try {
            ps = conn.prepareStatement(sql);
            bindParams(ps, p);
            return ps.executeUpdate();
        } finally {
            closeAll(null, ps, null);
        }
    }

    // ---- 문자열 · 날짜 · 금액 유틸
    private String nvl(String s, String def) {
        return (s == null || s.length() == 0) ? def : s;
    }

    private int toInt(String s, int def) {
        try {
            return Integer.parseInt(s.trim().replaceAll(",", ""));
        } catch (Exception e) {
            return def;
        }
    }

    private long toLong(String s, long def) {
        try {
            return Long.parseLong(s.trim().replaceAll(",", ""));
        } catch (Exception e) {
            return def;
        }
    }

    /** HTML 출력용 이스케이프 */
    private String esc(Object o) {
        if (o == null) return "";
        return o.toString().replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
    }

    /** JSON 문자열용 이스케이프 */
    private String jq(Object o) {
        if (o == null) return "";
        return o.toString().replace("\\", "\\\\").replace("\"", "\\\"").replace("\r", "").replace("\n", "\\n");
    }

    private String fmtAmt(Object o) {          // 금액 서식 (DB 에서 읽은 BigDecimal · Long 도 그대로 넘긴다)
        return new DecimalFormat("#,##0").format(o == null ? 0L : ((Number) o).longValue());
    }

    private String today(String fmt) {
        return new SimpleDateFormat(fmt).format(new java.util.Date());
    }

    /** yyyy-MM-dd 기준으로 일수 더하기 */
    private String addDays(String ymd, int days) {
        try {
            SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
            Calendar cal = Calendar.getInstance();
            cal.setTime(sdf.parse(ymd));
            cal.add(Calendar.DAY_OF_MONTH, days);
            return sdf.format(cal.getTime());
        } catch (ParseException e) {
            throw new IllegalArgumentException("날짜 형식 오류 : " + ymd);
        }
    }

    /** 접두어 + 일시 + 일련번호 (예: OD20191105103015007) */
    private synchronized String genId(String prefix) {
        idSeq = (idSeq + 1) % 1000;
        return prefix + today("yyyyMMddHHmmss") + String.format("%03d", idSeq);
    }

    /** 공급가액으로 세액 계산 (원 단위 반올림) */
    private long calcVat(long supplyAmt) {
        return Math.round(supplyAmt * VAT_RATE);
    }

    /** 조회 결과를 JSON 배열 문자열로 : 컬럼명 CUST_NM -> custNm, 숫자는 그대로 나머지는 문자열 (2019.08 홍길동) */
    private String toJson(List<HashMap<String, Object>> list) {
        StringBuffer sb = new StringBuffer("[");
        for (int i = 0; i < list.size(); i++) {
            sb.append(i > 0 ? ",{" : "{");
            int j = 0;
            for (Map.Entry<String, Object> en : list.get(i).entrySet()) {
                StringBuffer sbKey = new StringBuffer();
                boolean bUp = false;
                for (char ch : en.getKey().toLowerCase().toCharArray()) {
                    if (ch == '_') { bUp = true; continue; }
                    sbKey.append(bUp ? Character.toUpperCase(ch) : ch);
                    bUp = false;
                }
                Object v = en.getValue();
                sb.append((j++ > 0 ? "," : "") + "\"" + sbKey + "\":" + (v instanceof Number ? v.toString() : "\"" + jq(v) + "\""));
            }
            sb.append("}");
        }
        return sb.append("]").toString();
    }

    private void printJson(HttpServletResponse res, JspWriter out, String json) throws IOException {
        out.clear();
        res.setContentType("application/json; charset=UTF-8");
        out.print(json);
        out.flush();
    }

    /** 처리 cmd 가 실패했을 때 JSON 으로 오류 메시지를 돌려준다 / 화면 cmd 는 화면 위에 빨간 글씨로 */
    private void printFail(HttpServletResponse res, JspWriter out, Exception e) throws IOException {
        printJson(res, out, "{\"ok\":false,\"msg\":\"" + jq(e.getMessage()) + "\"}");
    }

    private void printErr(JspWriter out, String what, Exception e) throws IOException {
        out.print("<p class=\"err\">" + what + " 오류 : " + esc(e.getMessage()) + "</p>");
    }

    // ---- 공통코드 (TB_CODE) : application 범위에 그룹별로 올려 두고 모든 화면이 같이 쓴다 (2019.08 홍길동)
    private synchronized HashMap<String, List<String[]>> loadCodeCache(boolean force) {
        ServletContext app = getServletContext();
        HashMap<String, List<String[]>> cache = (HashMap<String, List<String[]>>) app.getAttribute(CODE_CACHE);
        Long loadedAt = (Long) app.getAttribute(CODE_CACHE + "_AT");
        // 10분이 지나면 다시 읽는다 (600000 = 10분)
        if (!force && cache != null && loadedAt != null && System.currentTimeMillis() - loadedAt.longValue() < 600000L) {
            return cache;
        }
        Connection conn = null;
        cache = new HashMap<String, List<String[]>>();
        try {
            conn = getConn();
            List<HashMap<String, Object>> rows = queryList(conn,
                "SELECT GRP_CD, CD, CD_NM FROM TB_CODE WHERE USE_YN = 'Y' ORDER BY GRP_CD, SORT_ORD, CD", null);
            for (HashMap<String, Object> r : rows) {
                String strGrp = (String) r.get("GRP_CD");
                if (!cache.containsKey(strGrp)) {
                    cache.put(strGrp, new ArrayList<String[]>());
                }
                cache.get(strGrp).add(new String[] { (String) r.get("CD"), (String) r.get("CD_NM") });
            }
            app.setAttribute(CODE_CACHE, cache);
            app.setAttribute(CODE_CACHE + "_AT", Long.valueOf(System.currentTimeMillis()));
        } catch (Exception e) {
            e.printStackTrace();
        } finally {
            closeAll(null, null, conn);
        }
        return cache;
    }

    private String codeName(String grpCd, String cd) {
        if (cd == null) return "";
        List<String[]> list = loadCodeCache(false).get(grpCd);
        if (list != null) {
            for (String[] c : list) {
                if (c[0].equals(cd)) return c[1];
            }
        }
        return cd;
    }

    private List<String[]> codeList(String grpCd) {
        List<String[]> list = loadCodeCache(false).get(grpCd);
        return list == null ? new ArrayList<String[]>() : list;
    }

    /** 공통코드 드롭다운 HTML */
    private String codeSelect(String name, String grpCd, String sel, String allLabel) {
        StringBuffer sb = new StringBuffer("<select name=\"" + name + "\" id=\"" + name + "\">");
        if (allLabel != null) sb.append("<option value=\"\">" + allLabel + "</option>");
        for (String[] c : codeList(grpCd)) {
            sb.append("<option value=\"" + c[0] + "\"" + (c[0].equals(sel) ? " selected" : "") + ">" + c[1] + "</option>");
        }
        return sb.append("</select>").toString();
    }

    // ---- 여러 화면이 같이 부르는 업무 메서드

    /** 여신상태 변경 (01 정상 / 02 미수발생 / 03 연체) - 청구 · 수주완료 · 수금 · 배치에서 같이 쓴다 (2019.08 홍길동) */
    private int updateCreditStatus(Connection conn, String custId, String status) throws SQLException {
        return execUpdate(conn, "UPDATE TB_CUSTOMER SET CREDIT_STATUS = ?, UPD_DT = NOW() WHERE CUST_ID = ?",
                new Object[] { status, custId });
    }

    /** 거래처 미수 합계 = 발행된 청구 합계 - 수금 합계 */
    private long custArrearsAmt(Connection conn, String custId) throws SQLException {
        long lBill = queryLong(conn, "SELECT IFNULL(SUM(TOTAL_AMT), 0) FROM TB_BILL WHERE CUST_ID = ? AND ISSUE_STATUS = '10'",
                new Object[] { custId }, 0L);
        long lPaid = queryLong(conn, "SELECT IFNULL(SUM(COLLECT_AMT), 0) FROM TB_COLLECT WHERE CUST_ID = ?",
                new Object[] { custId }, 0L);
        return lBill - lPaid;
    }

    /** 기준일 단가 : 기간별 단가가 있으면 그것을, 없으면 제품 기본단가 (2020.02 김철수) */
    private long getUnitPrice(Connection conn, String productId, String baseDt) throws SQLException {
        String sql = "SELECT IFNULL((SELECT PP.UNIT_PRICE FROM TB_PRODUCT_PRICE PP "
                   + "WHERE PP.PRODUCT_ID = P.PRODUCT_ID AND ? BETWEEN PP.APPLY_FROM_DT AND PP.APPLY_TO_DT "
                   + "ORDER BY PP.APPLY_FROM_DT DESC LIMIT 1), P.UNIT_PRICE) "
                   + "FROM TB_PRODUCT P WHERE P.PRODUCT_ID = ?";
        return queryLong(conn, sql, new Object[] { baseDt, productId }, -1L);
    }

    /** 수주 상태 변경 : 접수 -> 계약완료 -> 청구완료 -> 수금완료 (취소) */
    private int changeOrderStatus(Connection conn, String orderId, String status) throws SQLException {
        return execUpdate(conn, "UPDATE TB_ORDER SET ORDER_STATUS = ?, UPD_DT = NOW() WHERE ORDER_ID = ?",
                new Object[] { status, orderId });
    }

    // ---- 외부 연동

    /** 전자세금계산서 서버에 발행 요청 (승인번호 반환).  실패하면 IOException */
    private String callEtax(String billId, String bizNo, String addr, long supplyAmt, long taxAmt) throws IOException {
        HttpURLConnection hc = (HttpURLConnection) new URL(ETAX_URL).openConnection();
        try {
            hc.setRequestMethod("POST");
            hc.setConnectTimeout(5000);
            hc.setReadTimeout(10000);
            hc.setDoOutput(true);
            hc.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
            // TODO: JSON 라이브러리로 교체
            String strBody = "{\"billId\":\"" + billId + "\",\"bizNo\":\"" + bizNo + "\",\"addr\":\"" + addr
                           + "\",\"supplyAmt\":" + supplyAmt + ",\"taxAmt\":" + taxAmt + "}";
            OutputStream os = hc.getOutputStream();
            os.write(strBody.getBytes("UTF-8"));
            os.close();
            if (hc.getResponseCode() != 200) {
                throw new IOException("전자세금계산서 발행 실패 : HTTP " + hc.getResponseCode());
            }
            BufferedReader br = new BufferedReader(new InputStreamReader(hc.getInputStream(), "UTF-8"));
            StringBuffer sb = new StringBuffer();
            String line;
            while ((line = br.readLine()) != null) sb.append(line);
            br.close();
            // 응답 예) {"etaxNo":"20191105-12345678"}
            String strRes = sb.toString();
            int iIdx = strRes.indexOf("\"etaxNo\":\"");
            if (iIdx < 0) throw new IOException("승인번호가 없는 응답 : " + strRes);
            int iStart = iIdx + 10;
            return strRes.substring(iStart, strRes.indexOf("\"", iStart));
        } finally {
            hc.disconnect();
        }
    }

    /** 메일 발송 (JavaMail 을 안 넣어서 SMTP 를 직접 쓴다. 인증 없는 사내 릴레이 전용) */
    private boolean sendMail(String to, String subject, String body) {
        Socket sock = null;
        try {
            sock = new Socket(MAIL_HOST, 25);
            sock.setSoTimeout(10000);
            BufferedReader br = new BufferedReader(new InputStreamReader(sock.getInputStream(), "UTF-8"));
            OutputStream os = sock.getOutputStream();
            br.readLine();
            String strSubj = "=?UTF-8?B?" + Base64.getEncoder().encodeToString(subject.getBytes("UTF-8")) + "?=";
            String[] arrCmd = { "HELO sms.example.com", "MAIL FROM:<" + MAIL_FROM + ">", "RCPT TO:<" + to + ">", "DATA",
                                "From: " + MAIL_FROM + "\r\nTo: " + to + "\r\nSubject: " + strSubj
                              + "\r\nContent-Type: text/plain; charset=UTF-8\r\n\r\n" + body + "\r\n.", "QUIT" };
            for (int i = 0; i < arrCmd.length; i++) {
                os.write((arrCmd[i] + "\r\n").getBytes("UTF-8"));
                os.flush();
                br.readLine();
            }
            return true;
        } catch (Exception e) {
            return false;       // 실패해도 배치는 계속 돈다
        } finally {
            try { if (sock != null) sock.close(); } catch (Exception e) { }
        }
    }

    // ---- 매출 리포트 SQL 조각 : 화면(salesReport)과 엑셀(salesExcel)이 같이 쓴다 (2021.03 김철수)
    private String salesFromSql() {
        return " FROM TB_CUSTOMER C"
             + " INNER JOIN TB_ORDER O ON O.CUST_ID = C.CUST_ID"
             + " INNER JOIN TB_ORDER_ITEM OI ON OI.ORDER_ID = O.ORDER_ID"
             + " INNER JOIN TB_PRODUCT P ON P.PRODUCT_ID = OI.PRODUCT_ID"
             + " LEFT OUTER JOIN TB_USER U ON U.USER_ID = C.CHARGE_USER_ID"
             + " LEFT OUTER JOIN TB_BILL B ON B.ORDER_ID = O.ORDER_ID"
             + " LEFT OUTER JOIN TB_COLLECT CL ON CL.BILL_ID = B.BILL_ID";
    }

    private String salesWhereSql(HttpServletRequest req, List<Object> params, String authCd, String loginId) {
        StringBuffer sb = new StringBuffer(" WHERE O.ORDER_STATUS != '취소'");
        if (nvl(req.getParameter("fromDt"), "").length() > 0) { sb.append(" AND O.ORDER_DT >= ?"); params.add(req.getParameter("fromDt")); }
        if (nvl(req.getParameter("toDt"), "").length() > 0) { sb.append(" AND O.ORDER_DT <= ?"); params.add(req.getParameter("toDt")); }
        if (nvl(req.getParameter("custId"), "").length() > 0) { sb.append(" AND C.CUST_ID = ?"); params.add(req.getParameter("custId")); }
        if (nvl(req.getParameter("productId"), "").length() > 0) { sb.append(" AND P.PRODUCT_ID = ?"); params.add(req.getParameter("productId")); }
        if ("USER".equals(authCd)) {                       // 영업사원은 본인 담당 거래처만
            sb.append(" AND C.CHARGE_USER_ID = ?");
            params.add(loginId);
        }
        return sb.toString();
    }

    // ---- 배치에서 부르는 일괄 처리 (batchArrears / batchClose / batchAll 이 같이 쓴다)

    /** 미수 안내 : 30일 넘은 미수가 있는 거래처 대표 담당자에게 메일 (거래처당 1통) */
    private String runArrearsNotice(Connection conn) throws Exception {
        List<HashMap<String, Object>> list = queryList(conn,
            "SELECT B.BILL_ID, B.CUST_ID, C.CUST_NM, B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) AS ARREARS_AMT, "
          + "DATEDIFF(NOW(), B.BILL_DT) AS OVERDUE_DAYS "
          + "FROM TB_BILL B INNER JOIN TB_CUSTOMER C ON C.CUST_ID = B.CUST_ID "
          + "LEFT OUTER JOIN (SELECT BILL_ID, SUM(COLLECT_AMT) AS PAID_AMT FROM TB_COLLECT GROUP BY BILL_ID) P ON P.BILL_ID = B.BILL_ID "
          + "WHERE B.ISSUE_STATUS = '10' AND B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) > 0 AND DATEDIFF(NOW(), B.BILL_DT) >= 30 "
          + "ORDER BY OVERDUE_DAYS DESC", null);
        Set<String> noticed = new HashSet<String>();
        int iSent = 0;
        for (HashMap<String, Object> r : list) {
            String strCustId = (String) r.get("CUST_ID");
            if (!noticed.add(strCustId)) continue;          // 거래처당 하루 한 번만
            HashMap<String, Object> contact = queryOne(conn,
                "SELECT CONTACT_NM, EMAIL FROM TB_CUST_CONTACT WHERE CUST_ID = ? AND EMAIL IS NOT NULL "
              + "ORDER BY MAIN_YN DESC, CONTACT_ID LIMIT 1", new Object[] { strCustId });
            if (contact == null) continue;
            String strBody = contact.get("CONTACT_NM") + " 님,\n\n" + r.get("CUST_NM") + " 의 미수금 "
                           + fmtAmt(r.get("ARREARS_AMT")) + "원이 " + r.get("OVERDUE_DAYS") + "일 경과했습니다. 확인 부탁드립니다.\n";
            if (sendMail((String) contact.get("EMAIL"), "[SMS] 미수금 안내", strBody)) {
                execUpdate(conn, "UPDATE TB_CUSTOMER SET LAST_NOTICE_DT = NOW() WHERE CUST_ID = ?", new Object[] { strCustId });
                updateCreditStatus(conn, strCustId, "03");
                iSent++;
            }
        }
        return "미수 안내 메일 " + iSent + "건";
    }

    /** 월마감 : 수금까지 끝난 수주 · 발행 완료된 청구를 마감 처리 (대상 표를 배열로 돌린다) */
    private String runMonthClose(Connection conn, String closeYm) throws SQLException {
        String[] arrTbl  = { "TB_ORDER", "TB_BILL" };
        String[] arrDtCol = { "ORDER_DT", "BILL_DT" };
        String[] arrCond = { "ORDER_STATUS = '수금완료'", "ISSUE_STATUS = '10'" };
        StringBuffer sbRes = new StringBuffer(closeYm + " 마감 :");
        for (int i = 0; i < arrTbl.length; i++) {
            int iCnt = execUpdate(conn, "UPDATE " + arrTbl[i] + " SET CLOSE_YN = 'Y', CLOSE_YM = ?, UPD_DT = NOW() "
                + "WHERE " + arrCond[i] + " AND CLOSE_YN = 'N' AND DATE_FORMAT(" + arrDtCol[i] + ", '%Y%m') <= ?",
                new Object[] { closeYm, closeYm });
            sbRes.append(" " + arrTbl[i] + " " + iCnt + "건");
        }
        return sbRes.toString();
    }

    /** 유효기한이 지난 견적은 종결(90) 처리 */
    private int expireQuotes(Connection conn) throws SQLException {
        return execUpdate(conn, "UPDATE TB_QUOTE SET STATUS_CD = '90', UPD_DT = NOW() "
                              + "WHERE STATUS_CD IN ('10', '20') AND VALID_DT < CURDATE()", null);
    }

    // ---- 2018.01 수주 이력을 따로 쌓던 시절 코드.  TB_ORDER_HIST · TB_CUST_HIST 는 2018.11 에 삭제됨 (지우지는 않았음)
    private void backupOrderToHist(Connection conn, String orderId) throws SQLException {
        execUpdate(conn, "INSERT INTO TB_ORDER_HIST (ORDER_ID, CUST_ID, ORDER_AMT, ORDER_STATUS, HIST_DT) "
                       + "SELECT ORDER_ID, CUST_ID, ORDER_AMT, ORDER_STATUS, NOW() FROM TB_ORDER WHERE ORDER_ID = ?",
                   new Object[] { orderId });
    }

    private List<HashMap<String, Object>> getCustHistory(Connection conn, String custId) throws SQLException {
        return queryList(conn, "SELECT CUST_ID, CHG_COL, OLD_VAL, NEW_VAL, CHG_DT FROM TB_CUST_HIST "
                             + "WHERE CUST_ID = ? ORDER BY CHG_DT DESC", new Object[] { custId });
    }
%>
<%
    // ================================================================
    //  공통 처리 : 인코딩 · cmd 결정 · 로그인 검사
    // ================================================================
    request.setCharacterEncoding("UTF-8");
    String cmd = nvl(request.getParameter("cmd"), "main");
    String ctxPath = request.getContextPath();
    String thisPage = ctxPath + "/sales_main.jsp";
    boolean bAjax = "XMLHttpRequest".equals(request.getHeader("X-Requested-With"));

    // 로그인 사용자 : 로그인 때 세션에 HashMap 으로 넣어 둔다 (USER_ID, USER_NM, DEPT_ID, DEPT_NM, AUTH_CD, AUTH_NM)
    HashMap loginUser = (HashMap) session.getAttribute("LOGIN_USER");
    String loginId = loginUser == null ? "" : (String) loginUser.get("USER_ID");
    String loginNm = loginUser == null ? "" : (String) loginUser.get("USER_NM");
    String authCd  = loginUser == null ? "" : (String) loginUser.get("AUTH_CD");

    // 로그인 없이 부를 수 있는 cmd : 로그인 화면 · 로그인 처리 · 배치(key 로 확인)
    boolean bPublic = "login".equals(cmd) || "doLogin".equals(cmd) || cmd.startsWith("batch");
    if (!bPublic && loginUser == null) {
        if (bAjax) {
            response.setStatus(401);
            printJson(response, out, "{\"ok\":false,\"msg\":\"로그인이 필요합니다.\"}");
        } else {
            response.sendRedirect(thisPage + "?cmd=login");
        }
        return;
    }
    // 관리자만 부를 수 있는 cmd (메뉴에서도 숨기지만 여기서도 막는다)
    if (("codeSave".equals(cmd) || "cacheReload".equals(cmd)) && !"ADMIN".equals(authCd)) {
        printJson(response, out, "{\"ok\":false,\"msg\":\"권한이 없습니다.\"}");
        return;
    }
%>
<%
    // ================================================================
    //  [처리 전용 cmd]  화면 없이 JSON 으로 답하거나 redirect / 다운로드 한다
    //  (화면이 있는 cmd 는 이 아래 [화면 cmd] 분기에 있다)
    // ================================================================
    if ("doLogin".equals(cmd)) {
        // ---------------------------------------------------------- 로그인 처리
        String strUserId = nvl(request.getParameter("userId"), "").trim();
        String strPasswd = nvl(request.getParameter("passwd"), "");
        Connection conn = null;
        try {
            conn = getConn();
            HashMap<String, Object> row = queryOne(conn,
                "SELECT U.USER_ID, U.USER_NM, U.DEPT_ID, D.DEPT_NM, U.AUTH_CD, A.AUTH_NM, U.EMAIL "
              + "FROM TB_USER U LEFT OUTER JOIN TB_DEPT D ON D.DEPT_ID = U.DEPT_ID "
              + "LEFT OUTER JOIN TB_AUTH A ON A.AUTH_CD = U.AUTH_CD "
              + "WHERE U.USER_ID = ? AND U.PASSWD = SHA2(?, 256) AND U.USE_YN = 'Y'",
                new Object[] { strUserId, strPasswd });
            if (row == null) {
                response.sendRedirect(thisPage + "?cmd=login&err=1");
                return;
            }
            HashMap<String, String> lu = new HashMap<String, String>();
            for (String k : new String[] { "USER_ID", "USER_NM", "DEPT_ID", "DEPT_NM", "AUTH_CD", "AUTH_NM" }) {
                lu.put(k, (String) row.get(k));
            }
            session.setAttribute("LOGIN_USER", lu);
            session.setMaxInactiveInterval(60 * 60);            // 1시간
            execUpdate(conn, "UPDATE TB_USER SET LAST_LOGIN_DT = NOW() WHERE USER_ID = ?", new Object[] { strUserId });
            response.sendRedirect(thisPage + "?cmd=main");
            return;
        } catch (Exception e) {
            e.printStackTrace();
            response.sendRedirect(thisPage + "?cmd=login&err=2");
            return;
        } finally {
            closeAll(null, null, conn);
        }
    } else if ("logout".equals(cmd)) {
        session.invalidate();
        response.sendRedirect(thisPage + "?cmd=login");
        return;
    } else if ("codeSave".equals(cmd)) {
        // ---------------------------------------------------------- 공통코드 등록 / 수정 (관리자)
        Connection conn = null;
        try {
            conn = getConn();
            execUpdate(conn, "INSERT INTO TB_CODE (GRP_CD, CD, CD_NM, SORT_ORD, USE_YN) VALUES (?, ?, ?, ?, ?) "
                           + "ON DUPLICATE KEY UPDATE CD_NM = VALUES(CD_NM), SORT_ORD = VALUES(SORT_ORD), USE_YN = VALUES(USE_YN)",
                new Object[] { request.getParameter("grpCd"), request.getParameter("cd"), request.getParameter("cdNm"),
                               toInt(request.getParameter("sortOrd"), 0), nvl(request.getParameter("useYn"), "Y") });
            loadCodeCache(true);        // 이 서버의 캐시만 바로 갱신된다 (WAS 가 2대면 다른 쪽은 10분 뒤)
            printJson(response, out, "{\"ok\":true}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("cacheReload".equals(cmd)) {
        // ---------------------------------------------------------- 공통코드 캐시 갱신 (화면의 [캐시 갱신] 버튼)
        loadCodeCache(true);
        printJson(response, out, "{\"ok\":true}");
        return;
    } else if ("noticeSave".equals(cmd)) {
        // ---------------------------------------------------------- 공지 등록 (관리자 · 팀장)
        if ("USER".equals(authCd)) {
            printJson(response, out, "{\"ok\":false,\"msg\":\"권한이 없습니다.\"}");
            return;
        }
        Connection conn = null;
        try {
            conn = getConn();
            execUpdate(conn, "INSERT INTO TB_NOTICE (TITLE, CONTENT, WRITER_ID, VIEW_CNT, TOP_YN, REG_DT) VALUES (?, ?, ?, 0, ?, NOW())",
                new Object[] { request.getParameter("title"), request.getParameter("content"), loginId,
                               "Y".equals(request.getParameter("topYn")) ? "Y" : "N" });
            printJson(response, out, "{\"ok\":true}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("masterExport".equals(cmd)) {
        // ---------------------------------------------------------- 기준정보 엑셀 내려받기 (표 이름은 화면에서 받는다)
        //   tbl = CODE / PRODUCT / CUSTOMER / USER ... (TB_ 뒤에 붙는 이름)   2018.05 김철수
        String strTbl = nvl(request.getParameter("tbl"), "CODE").toUpperCase();
        String strOrderBy = nvl(request.getParameter("orderBy"), "1");
        Connection conn = null;
        Statement st = null;
        ResultSet rs = null;
        try {
            conn = getConn();
            st = conn.createStatement();
            rs = st.executeQuery("SELECT * FROM TB_" + strTbl + " ORDER BY " + strOrderBy);
            out.clear();
            response.setContentType("application/vnd.ms-excel; charset=UTF-8");
            response.setHeader("Content-Disposition", "attachment; filename=" + strTbl + "_" + today("yyyyMMdd") + ".xls");
            ResultSetMetaData md = rs.getMetaData();
            out.println("<table border=\"1\"><tr>");
            for (int i = 1; i <= md.getColumnCount(); i++) {
                out.println("<th>" + md.getColumnLabel(i) + "</th>");
            }
            out.println("</tr>");
            while (rs.next()) {
                out.print("<tr>");
                for (int i = 1; i <= md.getColumnCount(); i++) {
                    out.print("<td>" + esc(rs.getString(i)) + "</td>");
                }
                out.println("</tr>");
            }
            out.println("</table>");
        } catch (Exception e) {
            out.print("다운로드 중 오류 : " + esc(e.getMessage()));
        } finally {
            closeAll(rs, st, conn);
        }
        return;
    } else if ("custListData".equals(cmd)) {
        // ---------------------------------------------------------- 거래처 목록 (JSON) : 거래처 화면 · 대시보드 · 수주 팝업이 같이 부른다
        int iPageNo = toInt(request.getParameter("pageNo"), 1);
        int iPageSize = toInt(request.getParameter("pageSize"), 20);
        if (iPageSize > 100) iPageSize = 20;                // 100건 넘게 달라고 하면 20 으로 (왜 20 인지 기억 안 남)
        StringBuffer sbWhere = new StringBuffer(" WHERE C.USE_YN = 'Y'");
        List<Object> params = new ArrayList<Object>();
        String strSearchWord = nvl(request.getParameter("searchWord"), "");
        if (strSearchWord.length() > 0) {                   // 거래처명 · 대표자 일부 일치 또는 사업자번호 일치
            sbWhere.append(" AND (C.CUST_NM LIKE CONCAT('%', ?, '%') OR C.CEO_NM LIKE CONCAT('%', ?, '%') OR C.BIZ_NO = ?)");
            params.add(strSearchWord);
            params.add(strSearchWord);
            params.add(strSearchWord);
        }
        if (nvl(request.getParameter("creditStatus"), "").length() > 0) {
            sbWhere.append(" AND C.CREDIT_STATUS = ?");
            params.add(request.getParameter("creditStatus"));
        }
        if ("USER".equals(authCd)) {                        // 영업사원은 본인 담당 거래처만
            sbWhere.append(" AND C.CHARGE_USER_ID = ?");
            params.add(loginId);
        }
        // 정렬 컬럼은 화면에서 받은 값을 그대로 쓴다 (2018.09 김철수 - 대시보드에서 최근 등록순으로 부르려고)
        String strSortCol = nvl(request.getParameter("sortCol"), "C.CUST_NM");
        String strSortDir = "DESC".equals(request.getParameter("sortDir")) ? "DESC" : "ASC";
        Connection conn = null;
        try {
            conn = getConn();
            int iTotal = (int) queryLong(conn, "SELECT COUNT(*) FROM TB_CUSTOMER C" + sbWhere, params.toArray(), 0L);
            params.add((iPageNo - 1) * iPageSize);
            params.add(iPageSize);
            List<HashMap<String, Object>> list = queryList(conn,
                "SELECT C.CUST_ID, C.CUST_NM, C.BIZ_NO, C.CEO_NM, C.TEL_NO, C.CUST_GRADE, C.CREDIT_STATUS, C.CREDIT_LIMIT, "
              + "C.REG_DT, U.USER_NM AS CHARGE_USER_NM FROM TB_CUSTOMER C "
              + "LEFT OUTER JOIN TB_USER U ON U.USER_ID = C.CHARGE_USER_ID" + sbWhere
              + " ORDER BY " + strSortCol + " " + strSortDir + " LIMIT ?, ?", params.toArray());
            for (HashMap<String, Object> r : list) {            // 코드명은 공통코드 캐시에서
                r.put("CUST_GRADE_NM", codeName("CUST_GRADE", (String) r.get("CUST_GRADE")));
                r.put("CREDIT_STATUS_NM", codeName("CREDIT_STATUS", (String) r.get("CREDIT_STATUS")));
            }
            printJson(response, out, "{\"ok\":true,\"totalCnt\":" + iTotal + ",\"list\":" + toJson(list) + "}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("custSave".equals(cmd)) {
        // ---------------------------------------------------------- 거래처 등록 / 수정 (신규일 때는 담당자 1명도 같이)
        String strCustId = nvl(request.getParameter("custId"), "");
        String strCustNm = nvl(request.getParameter("custNm"), "").trim();
        String strBizNo = nvl(request.getParameter("bizNo"), "").replaceAll("-", "");
        long lLimit = toLong(request.getParameter("creditLimit"), 0L);
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            if (strCustNm.length() == 0) throw new Exception("거래처명을 입력하세요.");
            if (strCustId.length() == 0) {
                // 신규 : 사업자번호 중복 검사
                long lDup = queryLong(conn, "SELECT COUNT(*) FROM TB_CUSTOMER WHERE BIZ_NO = ? AND USE_YN = 'Y'",
                        new Object[] { strBizNo }, 0L);
                if (lDup > 0) throw new Exception("이미 등록된 사업자번호입니다.");
                strCustId = genId("CU");
                execUpdate(conn, "INSERT INTO TB_CUSTOMER (CUST_ID, CUST_NM, BIZ_NO, CEO_NM, ADDR, ADDR_DTL, TEL_NO, CUST_GRADE, "
                               + "CREDIT_STATUS, CREDIT_LIMIT, CHARGE_USER_ID, USE_YN, REG_USER_ID, REG_DT) "
                               + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, '01', ?, ?, 'Y', ?, NOW())",
                    new Object[] { strCustId, strCustNm, strBizNo, request.getParameter("ceoNm"), request.getParameter("addr"),
                                   request.getParameter("addrDtl"), request.getParameter("telNo"), nvl(request.getParameter("custGrade"), "C"),
                                   lLimit > 0 ? Long.valueOf(lLimit) : null, nvl(request.getParameter("chargeUserId"), loginId), loginId });
                if (nvl(request.getParameter("contactNm"), "").length() > 0) {
                    execUpdate(conn, "INSERT INTO TB_CUST_CONTACT (CUST_ID, CONTACT_NM, DEPT_NM, POSITION_NM, EMAIL, MOBILE_NO, MAIN_YN, REG_DT) "
                                   + "VALUES (?, ?, ?, ?, ?, ?, 'Y', NOW())",
                        new Object[] { strCustId, request.getParameter("contactNm"), request.getParameter("contactDept"),
                                       request.getParameter("contactPos"), request.getParameter("contactEmail"), request.getParameter("contactMobile") });
                }
            } else {
                // 수정 : 한도를 현재 미수보다 낮게는 못 바꾼다 (청구 · 수금 합계를 직접 읽는다)
                long lArrears = custArrearsAmt(conn, strCustId);
                if (lLimit > 0 && lArrears > lLimit) {
                    throw new Exception("현재 미수금(" + fmtAmt(lArrears) + "원)이 여신한도보다 큽니다.");
                }
                execUpdate(conn, "UPDATE TB_CUSTOMER SET CUST_NM = ?, BIZ_NO = ?, CEO_NM = ?, ADDR = ?, ADDR_DTL = ?, TEL_NO = ?, "
                               + "CUST_GRADE = ?, CREDIT_LIMIT = ?, CHARGE_USER_ID = ?, UPD_DT = NOW() WHERE CUST_ID = ?",
                    new Object[] { strCustNm, strBizNo, request.getParameter("ceoNm"), request.getParameter("addr"),
                                   request.getParameter("addrDtl"), request.getParameter("telNo"), nvl(request.getParameter("custGrade"), "C"),
                                   lLimit > 0 ? Long.valueOf(lLimit) : null, nvl(request.getParameter("chargeUserId"), loginId), strCustId });
            }
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"custId\":\"" + strCustId + "\"}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("custDelete".equals(cmd)) {
        // ---------------------------------------------------------- 거래처 사용중지 (삭제는 USE_YN = 'N' 으로만)
        String strCustId = request.getParameter("custId");
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            if (custArrearsAmt(conn, strCustId) > 0) {          // 미수가 남아 있으면 못 끊는다
                throw new Exception("미수금이 남아 있는 거래처는 사용중지할 수 없습니다.");
            }
            execUpdate(conn, "UPDATE TB_CUSTOMER SET USE_YN = 'N', UPD_DT = NOW() WHERE CUST_ID = ?", new Object[] { strCustId });
            // 접수 상태 수주는 같이 취소한다 (2020.06 영업팀 요청)
            int iOrder = execUpdate(conn, "UPDATE TB_ORDER SET ORDER_STATUS = '취소', UPD_DT = NOW() WHERE CUST_ID = ? AND ORDER_STATUS = '접수'",
                    new Object[] { strCustId });
            // 아직 발행 전인 청구(00)는 실패(90)로 돌려 놓는다
            int iBill = execUpdate(conn, "UPDATE TB_BILL SET ISSUE_STATUS = '90', UPD_DT = NOW() WHERE CUST_ID = ? AND ISSUE_STATUS = '00'",
                    new Object[] { strCustId });
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"canceledOrder\":" + iOrder + ",\"canceledBill\":" + iBill + "}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("custCreditInfo".equals(cmd)) {
        // ---------------------------------------------------------- 거래처 여신 정보 (JSON) : 수주 등록 화면에서 부른다
        Connection conn = null;
        try {
            conn = getConn();
            HashMap<String, Object> cust = queryOne(conn, "SELECT CUST_NM, BIZ_NO, CREDIT_STATUS, CREDIT_LIMIT FROM TB_CUSTOMER WHERE CUST_ID = ?",
                    new Object[] { request.getParameter("custId") });
            if (cust == null) throw new Exception("거래처 정보가 없습니다.");
            long lArrears = custArrearsAmt(conn, request.getParameter("custId"));
            printJson(response, out, "{\"ok\":true,\"custNm\":\"" + jq(cust.get("CUST_NM")) + "\",\"creditStatus\":\"" + jq(cust.get("CREDIT_STATUS"))
                    + "\",\"creditLimit\":" + (cust.get("CREDIT_LIMIT") == null ? 0 : ((Number) cust.get("CREDIT_LIMIT")).longValue())
                    + ",\"arrears\":" + lArrears + "}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("prodSave".equals(cmd)) {
        // ---------------------------------------------------------- 제품 등록 / 수정
        String strProductId = nvl(request.getParameter("productId"), "");
        long lUnitPrice = toLong(request.getParameter("unitPrice"), -1L);
        Connection conn = null;
        try {
            conn = getConn();
            if (nvl(request.getParameter("productNm"), "").length() == 0 || lUnitPrice < 0) {
                throw new Exception("제품명과 기본단가를 확인하세요.");
            }
            if (strProductId.length() == 0) {
                strProductId = genId("PR");
                execUpdate(conn, "INSERT INTO TB_PRODUCT (PRODUCT_ID, PRODUCT_NM, PRODUCT_TYPE, UNIT_CD, UNIT_PRICE, USE_YN, REG_DT) "
                               + "VALUES (?, ?, ?, ?, ?, 'Y', NOW())",
                    new Object[] { strProductId, request.getParameter("productNm"), request.getParameter("productType"),
                                   request.getParameter("unitCd"), lUnitPrice });
            } else {
                execUpdate(conn, "UPDATE TB_PRODUCT SET PRODUCT_NM = ?, PRODUCT_TYPE = ?, UNIT_CD = ?, UNIT_PRICE = ?, UPD_DT = NOW() "
                               + "WHERE PRODUCT_ID = ?",
                    new Object[] { request.getParameter("productNm"), request.getParameter("productType"),
                                   request.getParameter("unitCd"), lUnitPrice, strProductId });
            }
            printJson(response, out, "{\"ok\":true,\"productId\":\"" + strProductId + "\"}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("priceSave".equals(cmd)) {
        // ---------------------------------------------------------- 기간별 단가 등록 (적용 기간이 겹치면 거부) 2020.02 김철수
        Connection conn = null;
        try {
            conn = getConn();
            String strFrom = request.getParameter("applyFromDt");
            String strTo = request.getParameter("applyToDt");
            long lDup = queryLong(conn, "SELECT COUNT(*) FROM TB_PRODUCT_PRICE WHERE PRODUCT_ID = ? AND ? <= APPLY_TO_DT AND ? >= APPLY_FROM_DT",
                    new Object[] { request.getParameter("productId"), strFrom, strTo }, 0L);
            if (lDup > 0) throw new Exception("적용 기간이 겹치는 단가가 있습니다.");
            execUpdate(conn, "INSERT INTO TB_PRODUCT_PRICE (PRODUCT_ID, CUST_GRADE, UNIT_PRICE, APPLY_FROM_DT, APPLY_TO_DT) VALUES (?, ?, ?, ?, ?)",
                new Object[] { request.getParameter("productId"), nvl(request.getParameter("custGrade"), null),
                               toLong(request.getParameter("unitPrice"), 0L), strFrom, strTo });
            printJson(response, out, "{\"ok\":true}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("priceInfo".equals(cmd)) {
        // ---------------------------------------------------------- 기준일 단가 조회 (JSON) : 견적 · 수주 화면의 품목 입력에서 부른다
        Connection conn = null;
        try {
            conn = getConn();
            long lPrice = getUnitPrice(conn, request.getParameter("productId"), nvl(request.getParameter("baseDt"), today("yyyy-MM-dd")));
            printJson(response, out, "{\"ok\":" + (lPrice >= 0) + ",\"unitPrice\":" + lPrice + ",\"msg\":\"단가가 없는 제품입니다.\"}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("opptySave".equals(cmd)) {
        // ---------------------------------------------------------- 영업기회 등록 (거래처 존재 여부는 거래처 표를 직접 확인)
        Connection conn = null;
        try {
            conn = getConn();
            long lCust = queryLong(conn, "SELECT COUNT(*) FROM TB_CUSTOMER WHERE CUST_ID = ? AND USE_YN = 'Y'",
                    new Object[] { request.getParameter("custId") }, 0L);
            if (lCust == 0) throw new Exception("거래처를 선택하세요.");
            String strOpptyId = genId("OP");
            execUpdate(conn, "INSERT INTO TB_OPPTY (OPPTY_ID, CUST_ID, OPPTY_NM, STAGE_CD, EXPECT_AMT, EXPECT_CLOSE_DT, CHARGE_USER_ID, STATUS_CD, REG_DT) "
                           + "VALUES (?, ?, ?, '10', ?, ?, ?, '10', NOW())",
                new Object[] { strOpptyId, request.getParameter("custId"), request.getParameter("opptyNm"),
                               toLong(request.getParameter("expectAmt"), 0L), nvl(request.getParameter("expectCloseDt"), null), loginId });
            printJson(response, out, "{\"ok\":true,\"opptyId\":\"" + strOpptyId + "\"}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("opptyStage".equals(cmd)) {
        // ---------------------------------------------------------- 영업기회 단계 변경 : 10 발굴 / 20 제안 / 30 협상 / 40 수주 / 90 실주
        String strStage = request.getParameter("stageCd");
        Connection conn = null;
        try {
            conn = getConn();
            execUpdate(conn, "UPDATE TB_OPPTY SET STAGE_CD = ?, STATUS_CD = CASE WHEN ? IN ('40', '90') THEN '90' ELSE '10' END, UPD_DT = NOW() "
                           + "WHERE OPPTY_ID = ?", new Object[] { strStage, strStage, request.getParameter("opptyId") });
            printJson(response, out, "{\"ok\":true}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("quoteSave".equals(cmd)) {
        // ---------------------------------------------------------- 견적 등록 : 품목 단가는 단가표에서 조회해서 채운다
        String[] arrProduct = request.getParameterValues("productId");
        String[] arrQty = request.getParameterValues("qty");
        String strOpptyId = nvl(request.getParameter("opptyId"), "");      // 영업기회 화면에서 넘어온 hidden 값
        String strQuoteDt = today("yyyy-MM-dd");
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            if (arrProduct == null || arrProduct.length == 0) throw new Exception("품목을 한 건 이상 입력하세요.");
            String strQuoteId = genId("QT");
            long lTotal = 0L;
            long[] arrUnit = new long[arrProduct.length];
            for (int i = 0; i < arrProduct.length; i++) {
                arrUnit[i] = getUnitPrice(conn, arrProduct[i], strQuoteDt);
                if (arrUnit[i] < 0) throw new Exception("단가가 없는 제품입니다 : " + arrProduct[i]);
                lTotal += arrUnit[i] * toInt(arrQty[i], 1);
            }
            execUpdate(conn, "INSERT INTO TB_QUOTE (QUOTE_ID, OPPTY_ID, CUST_ID, QUOTE_NM, QUOTE_DT, VALID_DT, TOTAL_AMT, STATUS_CD, CHARGE_USER_ID, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, ?, ?, '10', ?, NOW())",
                new Object[] { strQuoteId, nvl(strOpptyId, null), request.getParameter("custId"), request.getParameter("quoteNm"),
                               strQuoteDt, addDays(strQuoteDt, 30), lTotal, loginId });
            for (int i = 0; i < arrProduct.length; i++) {
                int iQty = toInt(arrQty[i], 1);
                execUpdate(conn, "INSERT INTO TB_QUOTE_ITEM (QUOTE_ID, ITEM_SEQ, PRODUCT_ID, QTY, UNIT_PRICE, AMT) VALUES (?, ?, ?, ?, ?, ?)",
                    new Object[] { strQuoteId, i + 1, arrProduct[i], iQty, arrUnit[i], arrUnit[i] * iQty });
            }
            // 영업기회에서 만든 견적이면 영업기회 단계를 '제안(20)' 으로 올린다
            if (strOpptyId.length() > 0) {
                execUpdate(conn, "UPDATE TB_OPPTY SET STAGE_CD = '20', UPD_DT = NOW() WHERE OPPTY_ID = ? AND STAGE_CD = '10'",
                    new Object[] { strOpptyId });
            }
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"quoteId\":\"" + strQuoteId + "\",\"totalAmt\":" + lTotal + "}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("quoteSubmit".equals(cmd)) {
        // ---------------------------------------------------------- 견적 제출 (작성 10 -> 제출 20)
        Connection conn = null;
        try {
            conn = getConn();
            int iCnt = execUpdate(conn, "UPDATE TB_QUOTE SET STATUS_CD = '20', UPD_DT = NOW() WHERE QUOTE_ID = ? AND STATUS_CD = '10'",
                    new Object[] { request.getParameter("quoteId") });
            printJson(response, out, "{\"ok\":" + (iCnt > 0) + ",\"msg\":\"이미 제출했거나 종결된 견적입니다.\"}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("orderListData".equals(cmd)) {
        // ---------------------------------------------------------- 수주 목록 (JSON) : 수주 화면 · 대시보드가 같이 부른다
        int iPageNo = toInt(request.getParameter("pageNo"), 1);
        int iPageSize = toInt(request.getParameter("pageSize"), 20);
        if (iPageSize > 100) iPageSize = 20;
        StringBuffer sbWhere = new StringBuffer(" WHERE 1 = 1");
        List<Object> params = new ArrayList<Object>();
        if (nvl(request.getParameter("custId"), "").length() > 0) {
            sbWhere.append(" AND O.CUST_ID = ?");
            params.add(request.getParameter("custId"));
        }
        if (nvl(request.getParameter("orderStatus"), "").length() > 0) {
            sbWhere.append(" AND O.ORDER_STATUS = ?");
            params.add(request.getParameter("orderStatus"));
        } else {
            sbWhere.append(" AND O.ORDER_STATUS != '취소'");
        }
        if ("USER".equals(authCd)) {                        // 영업사원은 본인 담당 거래처만
            sbWhere.append(" AND C.CHARGE_USER_ID = ?");
            params.add(loginId);
        }
        String strSortCol = nvl(request.getParameter("sortCol"), "O.ORDER_DT");
        String strSortDir = "ASC".equals(request.getParameter("sortDir")) ? "ASC" : "DESC";
        Connection conn = null;
        try {
            conn = getConn();
            int iTotal = (int) queryLong(conn, "SELECT COUNT(*) FROM TB_ORDER O LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID" + sbWhere,
                    params.toArray(), 0L);
            params.add((iPageNo - 1) * iPageSize);
            params.add(iPageSize);
            List<HashMap<String, Object>> list = queryList(conn,
                "SELECT O.ORDER_ID, O.QUOTE_ID, O.CUST_ID, C.CUST_NM, O.ORDER_DT, O.ORDER_AMT, O.ORDER_STATUS, O.CONTRACT_ID, O.CLOSE_YN "
              + "FROM TB_ORDER O LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID" + sbWhere
              + " ORDER BY " + strSortCol + " " + strSortDir + " LIMIT ?, ?", params.toArray());
            printJson(response, out, "{\"ok\":true,\"totalCnt\":" + iTotal + ",\"list\":" + toJson(list) + "}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("orderSave".equals(cmd)) {
        // ---------------------------------------------------------- 수주 등록 : 여신 검사 -> 단가 조회 -> TB_ORDER / TB_ORDER_ITEM 저장
        String strCustId = request.getParameter("custId");
        String strQuoteId = nvl(request.getParameter("quoteId"), "");      // 견적에서 넘어온 경우 hidden 값
        String[] arrProduct = request.getParameterValues("productId");
        String[] arrQty = request.getParameterValues("qty");
        String strOrderDt = today("yyyy-MM-dd");
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            // 1. 여신 검사 (2019.08 홍길동) : 거래처 한도 · 상태 · 현재 미수를 직접 읽는다
            HashMap<String, Object> cust = queryOne(conn, "SELECT CUST_NM, CREDIT_STATUS, CREDIT_LIMIT FROM TB_CUSTOMER WHERE CUST_ID = ? AND USE_YN = 'Y'",
                    new Object[] { strCustId });
            if (cust == null) throw new Exception("거래처 정보가 없습니다.");
            if ("03".equals(cust.get("CREDIT_STATUS"))) throw new Exception("연체 거래처는 수주를 등록할 수 없습니다.");
            if (arrProduct == null || arrProduct.length == 0) throw new Exception("품목을 한 건 이상 입력하세요.");
            // 2. 품목 단가는 제품 단가표에서 조회 (기준일 = 수주일)
            String strOrderId = genId("OD");
            long lOrderAmt = 0L;
            long[] arrUnit = new long[arrProduct.length];
            for (int i = 0; i < arrProduct.length; i++) {
                arrUnit[i] = getUnitPrice(conn, arrProduct[i], strOrderDt);
                if (arrUnit[i] < 0) throw new Exception("단가가 없는 제품입니다 : " + arrProduct[i]);
                lOrderAmt += arrUnit[i] * toInt(arrQty[i], 1);
            }
            long lLimit = cust.get("CREDIT_LIMIT") == null ? 0L : ((Number) cust.get("CREDIT_LIMIT")).longValue();
            if (lLimit > 0 && custArrearsAmt(conn, strCustId) + lOrderAmt > lLimit) {
                throw new Exception("여신한도를 초과합니다. (한도 " + fmtAmt(lLimit) + "원)");
            }
            execUpdate(conn, "INSERT INTO TB_ORDER (ORDER_ID, QUOTE_ID, CUST_ID, ORDER_DT, ORDER_AMT, ORDER_STATUS, CLOSE_YN, CHARGE_USER_ID, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, '접수', 'N', ?, NOW())",
                new Object[] { strOrderId, nvl(strQuoteId, null), strCustId, strOrderDt, lOrderAmt, loginId });
            for (int i = 0; i < arrProduct.length; i++) {
                int iQty = toInt(arrQty[i], 1);
                execUpdate(conn, "INSERT INTO TB_ORDER_ITEM (ORDER_ID, ITEM_SEQ, PRODUCT_ID, QTY, UNIT_PRICE, AMT) VALUES (?, ?, ?, ?, ?, ?)",
                    new Object[] { strOrderId, i + 1, arrProduct[i], iQty, arrUnit[i], arrUnit[i] * iQty });
            }
            // 3. 견적에서 만든 수주면 그 견적의 영업기회를 '수주(40)' 로 닫는다 (견적 표에서 영업기회 번호를 읽는다)
            if (strQuoteId.length() > 0) {
                HashMap<String, Object> q = queryOne(conn, "SELECT OPPTY_ID FROM TB_QUOTE WHERE QUOTE_ID = ?", new Object[] { strQuoteId });
                if (q != null && q.get("OPPTY_ID") != null) {
                    execUpdate(conn, "UPDATE TB_OPPTY SET STAGE_CD = '40', STATUS_CD = '90', UPD_DT = NOW() WHERE OPPTY_ID = ?",
                        new Object[] { q.get("OPPTY_ID") });
                }
            }
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"orderId\":\"" + strOrderId + "\",\"orderAmt\":" + lOrderAmt + "}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("orderComplete".equals(cmd)) {
        // ---------------------------------------------------------- 수주 완료 : 계약 생성 -> 청구 발행 -> 수주 상태 변경 -> 견적 종결
        //   2019.11.05 김철수 고객 요청으로 급히 추가.  전부 한 트랜잭션으로 묶었다 (중간에 실패하면 전부 롤백)
        String strOrderId = request.getParameter("orderId");
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            HashMap<String, Object> order = queryOne(conn,
                "SELECT O.ORDER_ID, O.QUOTE_ID, O.CUST_ID, O.ORDER_AMT, O.ORDER_STATUS, C.CUST_NM, C.BIZ_NO, C.ADDR "
              + "FROM TB_ORDER O INNER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID WHERE O.ORDER_ID = ? FOR UPDATE",
                new Object[] { strOrderId });
            if (order == null) throw new Exception("수주 정보가 없습니다 : " + strOrderId);
            if (!"접수".equals(order.get("ORDER_STATUS"))) throw new Exception("이미 처리된 수주입니다 : " + order.get("ORDER_STATUS"));
            String strCustId = (String) order.get("CUST_ID");
            long lOrderAmt = ((Number) order.get("ORDER_AMT")).longValue();

            // 1. 계약 생성 (기간 1년) + 수주에 계약번호를 달고 '계약완료' 로
            String strContractId = genId("CT");
            String strStartDt = today("yyyy-MM-dd");
            execUpdate(conn, "INSERT INTO TB_CONTRACT (CONTRACT_ID, ORDER_ID, CUST_ID, CONTRACT_NM, CONTRACT_AMT, START_DT, END_DT, STATUS_CD, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, ?, ?, '10', NOW())",
                new Object[] { strContractId, strOrderId, strCustId, order.get("CUST_NM") + " 계약", lOrderAmt, strStartDt, addDays(strStartDt, 365) });
            execUpdate(conn, "UPDATE TB_ORDER SET CONTRACT_ID = ?, ORDER_STATUS = '계약완료', UPD_DT = NOW() WHERE ORDER_ID = ?",
                new Object[] { strContractId, strOrderId });

            // 2. 청구 발행 + 전자세금계산서 요청 (외부 HTTP 호출이 트랜잭션 안에 있다)
            String strBillId = genId("BL");
            long lTax = calcVat(lOrderAmt);
            execUpdate(conn, "INSERT INTO TB_BILL (BILL_ID, ORDER_ID, CONTRACT_ID, CUST_ID, BILL_DT, SUPPLY_AMT, TAX_AMT, TOTAL_AMT, ISSUE_STATUS, CLOSE_YN, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, '00', 'N', NOW())",
                new Object[] { strBillId, strOrderId, strContractId, strCustId, strStartDt, lOrderAmt, lTax, lOrderAmt + lTax });
            String strEtaxNo = callEtax(strBillId, (String) order.get("BIZ_NO"), (String) order.get("ADDR"), lOrderAmt, lTax);
            execUpdate(conn, "UPDATE TB_BILL SET ETAX_NO = ?, ISSUE_STATUS = '10', UPD_DT = NOW() WHERE BILL_ID = ?",
                new Object[] { strEtaxNo, strBillId });
            updateCreditStatus(conn, strCustId, "02");                       // 청구가 나가면 거래처 여신상태를 '미수발생(02)' 으로

            // 3. 수주 상태 변경 · 견적 종결
            changeOrderStatus(conn, strOrderId, "청구완료");
            if (order.get("QUOTE_ID") != null) {
                execUpdate(conn, "UPDATE TB_QUOTE SET STATUS_CD = '90', UPD_DT = NOW() WHERE QUOTE_ID = ?", new Object[] { order.get("QUOTE_ID") });
            }
            // FIXME: 처리자(loginId) 이력 남기기
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"contractId\":\"" + strContractId + "\",\"billId\":\"" + strBillId + "\",\"etaxNo\":\"" + jq(strEtaxNo) + "\"}");
        } catch (Exception e) {
            rollbackQuietly(conn);          // 세금계산서는 이미 나갔어도 DB 만 되돌아간다
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("contractAmtUpdate".equals(cmd)) {
        // ---------------------------------------------------------- 계약 금액 변경 : 계약 금액이 바뀌면 수주 금액도 같이 맞춘다 (2020.09 김철수)
        String strContractId = request.getParameter("contractId");
        String strOrderId = request.getParameter("orderId");               // 화면의 hidden 값을 그대로 쓴다
        long lAmt = toLong(request.getParameter("contractAmt"), -1L);
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            if (lAmt < 0) throw new Exception("금액을 확인하세요.");
            execUpdate(conn, "UPDATE TB_CONTRACT SET CONTRACT_AMT = ?, UPD_DT = NOW() WHERE CONTRACT_ID = ?", new Object[] { lAmt, strContractId });
            execUpdate(conn, "UPDATE TB_ORDER SET ORDER_AMT = ?, UPD_DT = NOW() WHERE ORDER_ID = ?", new Object[] { lAmt, strOrderId });
            conn.commit();
            printJson(response, out, "{\"ok\":true}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("contractFile".equals(cmd)) {
        // ---------------------------------------------------------- 계약서 첨부 업로드 : 요청 본문에 파일 원본을 그대로 실어 보낸다 (화면의 XHR send(file))
        String strContractId = request.getParameter("contractId");
        String strFileNm = new File(nvl(request.getParameter("fileName"), "contract.dat")).getName();
        File dir = new File(UPLOAD_DIR + "/contract");
        if (!dir.exists()) dir.mkdirs();
        File saveFile = new File(dir, strContractId + "_" + strFileNm);
        InputStream is = request.getInputStream();
        FileOutputStream fos = new FileOutputStream(saveFile);
        byte[] buf = new byte[8192];
        int iRead;
        long lTotal = 0L;
        while ((iRead = is.read(buf)) != -1) {
            fos.write(buf, 0, iRead);
            lTotal += iRead;
        }
        fos.close();
        printJson(response, out, "{\"ok\":true,\"size\":" + lTotal + ",\"path\":\"" + jq(saveFile.getPath()) + "\"}");
        return;
    } else if ("billIssue".equals(cmd)) {
        // ---------------------------------------------------------- 청구 수기 발행 (수주 완료를 안 거치고 따로 발행할 때) 2016.09 김철수
        String strCustId = request.getParameter("custId");                 // 화면의 hidden 값
        String strOrderId = request.getParameter("orderId");               // 화면의 hidden 값
        String strContractId = nvl(request.getParameter("contractId"), null);
        long lSupply = toLong(request.getParameter("supplyAmt"), 0L);
        String strBillId = "";
        Connection conn = null;
        try {
            conn = getConn();
            // 세금계산서에 들어갈 사업자번호 · 주소는 거래처 표에서 직접 읽는다
            HashMap<String, Object> cust = queryOne(conn, "SELECT CUST_NM, BIZ_NO, ADDR FROM TB_CUSTOMER WHERE CUST_ID = ?", new Object[] { strCustId });
            if (cust == null) throw new Exception("거래처 정보가 없습니다 : " + strCustId);
            strBillId = genId("BL");
            long lTax = calcVat(lSupply);
            execUpdate(conn, "INSERT INTO TB_BILL (BILL_ID, ORDER_ID, CONTRACT_ID, CUST_ID, BILL_DT, SUPPLY_AMT, TAX_AMT, TOTAL_AMT, ISSUE_STATUS, CLOSE_YN, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, '00', 'N', NOW())",
                new Object[] { strBillId, strOrderId, strContractId, strCustId, today("yyyy-MM-dd"), lSupply, lTax, lSupply + lTax });
            String strEtaxNo = callEtax(strBillId, (String) cust.get("BIZ_NO"), (String) cust.get("ADDR"), lSupply, lTax);
            execUpdate(conn, "UPDATE TB_BILL SET ETAX_NO = ?, ISSUE_STATUS = '10', UPD_DT = NOW() WHERE BILL_ID = ?", new Object[] { strEtaxNo, strBillId });
            updateCreditStatus(conn, strCustId, "02");
            printJson(response, out, "{\"ok\":true,\"billId\":\"" + strBillId + "\",\"etaxNo\":\"" + jq(strEtaxNo) + "\"}");
        } catch (Exception e) {
            try {
                if (strBillId.length() > 0) {           // 발행 요청이 실패하면 청구를 실패(90)로 표시해 둔다
                    execUpdate(conn, "UPDATE TB_BILL SET ISSUE_STATUS = '90', UPD_DT = NOW() WHERE BILL_ID = ?", new Object[] { strBillId });
                }
            } catch (Exception e2) { }
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("billOpenList".equals(cmd)) {
        // ---------------------------------------------------------- 거래처의 미수 청구 목록 (JSON) : 수금 화면에서 청구를 고를 때 부른다
        Connection conn = null;
        try {
            conn = getConn();
            List<HashMap<String, Object>> list = queryList(conn,
                "SELECT B.BILL_ID, B.ORDER_ID, B.BILL_DT, B.TOTAL_AMT, "
              + "B.TOTAL_AMT - IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0) AS BALANCE "
              + "FROM TB_BILL B WHERE B.CUST_ID = ? AND B.ISSUE_STATUS = '10' "
              + "AND B.TOTAL_AMT - IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0) > 0 "
              + "ORDER BY B.BILL_DT, B.BILL_ID", new Object[] { request.getParameter("custId") });
            printJson(response, out, "{\"ok\":true,\"list\":" + toJson(list) + "}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("collectSave".equals(cmd)) {
        // ---------------------------------------------------------- 수금 등록 : 수금 -> (청구를 다 받으면) 수주 상태 -> 거래처 여신상태  (2020.04 홍길동 고객 요청)
        String strBillId = request.getParameter("billId");
        String strOrderId = request.getParameter("orderId");               // 화면의 hidden 값
        String strCustId = request.getParameter("custId");                 // 화면의 hidden 값
        long lAmt = toLong(request.getParameter("collectAmt"), 0L);
        Connection conn = null;
        try {
            conn = getConn();
            conn.setAutoCommit(false);
            if (lAmt <= 0L) throw new Exception("수금액을 확인하세요.");
            execUpdate(conn, "INSERT INTO TB_COLLECT (COLLECT_ID, BILL_ID, ORDER_ID, CUST_ID, COLLECT_DT, COLLECT_AMT, COLLECT_METHOD, REG_USER_ID, REG_DT) "
                           + "VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())",
                new Object[] { genId("CL"), strBillId, nvl(strOrderId, null), strCustId, nvl(request.getParameter("collectDt"), today("yyyy-MM-dd")),
                               lAmt, request.getParameter("collectMethod"), loginId });
            // 청구 건을 다 받았으면 수주 상태를 '수금완료' 로
            long lBalance = queryLong(conn, "SELECT B.TOTAL_AMT - IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0) "
                                          + "FROM TB_BILL B WHERE B.BILL_ID = ?", new Object[] { strBillId }, 1L);
            if (lBalance <= 0L) {
                changeOrderStatus(conn, strOrderId, "수금완료");
            }
            // 거래처 미수 합계에 따라 여신상태 변경 (미수 없음 01 / 미수 있음 02)
            updateCreditStatus(conn, strCustId, custArrearsAmt(conn, strCustId) <= 0L ? "01" : "02");
            conn.commit();
            printJson(response, out, "{\"ok\":true,\"balance\":" + lBalance + "}");
        } catch (Exception e) {
            rollbackQuietly(conn);
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("arrearsData".equals(cmd)) {
        // ---------------------------------------------------------- 미수 목록 (JSON) : 대시보드가 부른다.  화면(arrearsList)의 SQL 을 복사해 왔다 (2021.03)
        int iOverdue = toInt(request.getParameter("overdueDays"), 0);
        Connection conn = null;
        try {
            conn = getConn();
            List<HashMap<String, Object>> list = queryList(conn,
                "SELECT B.BILL_ID, B.CUST_ID, C.CUST_NM, B.BILL_DT, B.TOTAL_AMT, IFNULL(P.PAID_AMT, 0) AS PAID_AMT, "
              + "B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) AS ARREARS_AMT, DATEDIFF(NOW(), B.BILL_DT) AS OVERDUE_DAYS "
              + "FROM TB_BILL B INNER JOIN TB_CUSTOMER C ON C.CUST_ID = B.CUST_ID "
              + "LEFT OUTER JOIN (SELECT BILL_ID, SUM(COLLECT_AMT) AS PAID_AMT FROM TB_COLLECT GROUP BY BILL_ID) P ON P.BILL_ID = B.BILL_ID "
              + "WHERE B.ISSUE_STATUS = '10' AND B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) > 0 AND DATEDIFF(NOW(), B.BILL_DT) >= ? "
              + "ORDER BY OVERDUE_DAYS DESC, B.BILL_ID", new Object[] { iOverdue });
            printJson(response, out, "{\"ok\":true,\"list\":" + toJson(list) + "}");
        } catch (Exception e) {
            printFail(response, out, e);
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("salesExcel".equals(cmd)) {
        // ---------------------------------------------------------- 매출 상세 엑셀 : 조건은 salesReport 화면과 같다
        List<Object> params = new ArrayList<Object>();
        String strWhere = salesWhereSql(request, params, authCd, loginId);
        Connection conn = null;
        try {
            conn = getConn();
            List<HashMap<String, Object>> list = queryList(conn,
                "SELECT C.CUST_NM, U.USER_NM AS CHARGE_USER_NM, O.ORDER_ID, O.ORDER_DT, O.ORDER_STATUS, P.PRODUCT_NM, OI.QTY, OI.AMT AS ITEM_AMT, "
              + "B.TOTAL_AMT AS BILL_AMT, IFNULL(CL.COLLECT_AMT, 0) AS COLLECT_AMT" + salesFromSql() + strWhere
              + " ORDER BY O.ORDER_DT DESC, C.CUST_NM, P.PRODUCT_NM", params.toArray());
            out.clear();
            response.setContentType("application/vnd.ms-excel; charset=UTF-8");
            response.setHeader("Content-Disposition", "attachment; filename=sales_" + today("yyyyMMdd") + ".xls");
            out.println("<table border=\"1\"><tr><th>거래처</th><th>담당자</th><th>수주번호</th><th>수주일</th><th>상태</th><th>제품</th><th>수량</th><th>금액</th><th>청구금액</th><th>수금액</th></tr>");
            for (HashMap<String, Object> r : list) {
                out.println("<tr><td>" + esc(r.get("CUST_NM")) + "</td><td>" + esc(r.get("CHARGE_USER_NM")) + "</td><td>" + esc(r.get("ORDER_ID"))
                          + "</td><td>" + esc(r.get("ORDER_DT")) + "</td><td>" + esc(r.get("ORDER_STATUS")) + "</td><td>" + esc(r.get("PRODUCT_NM"))
                          + "</td><td>" + r.get("QTY") + "</td><td>" + r.get("ITEM_AMT") + "</td><td>" + esc(r.get("BILL_AMT")) + "</td><td>" + r.get("COLLECT_AMT") + "</td></tr>");
            }
            out.println("</table>");
        } catch (Exception e) {
            out.print("다운로드 중 오류 : " + esc(e.getMessage()));
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("batchArrears".equals(cmd)) {
        // ---------------------------------------------------------- 미수 안내 메일 배치 (평일 09:00 cron)   2022.05 홍길동
        if (!BATCH_KEY.equals(request.getParameter("key"))) {
            response.setStatus(403);
            out.print("forbidden");
            return;
        }
        Connection conn = null;
        try {
            conn = getConn();
            String strRes = runArrearsNotice(conn);
            out.clear();
            response.setContentType("text/plain; charset=UTF-8");
            out.print(strRes);
        } catch (Exception e) {
            out.print("ERROR " + e.getMessage());
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("batchClose".equals(cmd)) {
        // ---------------------------------------------------------- 월마감 배치 (매월 1일 01:30 cron) : 전월까지 마감   2022.05 홍길동
        if (!BATCH_KEY.equals(request.getParameter("key"))) {
            response.setStatus(403);
            out.print("forbidden");
            return;
        }
        Calendar calPrev = Calendar.getInstance();
        calPrev.add(Calendar.MONTH, -1);
        String strCloseYm = new SimpleDateFormat("yyyyMM").format(calPrev.getTime());
        Connection conn = null;
        try {
            conn = getConn();
            String strRes = runMonthClose(conn, strCloseYm);
            out.clear();
            response.setContentType("text/plain; charset=UTF-8");
            out.print(strRes);
        } catch (Exception e) {
            out.print("ERROR " + e.getMessage());
        } finally {
            closeAll(null, null, conn);
        }
        return;
    } else if ("batchAll".equals(cmd)) {
        // ---------------------------------------------------------- 일괄 배치 : 캐시 갱신 + 미수 안내 + 만료 견적 정리 + 월마감 + 결과 공지
        //   월초에 cron 이 한 번에 부른다 (2023.01 김철수).  동시에 두 번 돌지 않게 application 에 실행 중 표시를 남긴다
        if (!BATCH_KEY.equals(request.getParameter("key"))) {
            response.setStatus(403);
            out.print("forbidden");
            return;
        }
        if (application.getAttribute("BATCH_RUNNING") != null) {
            out.print("이미 실행 중 : " + application.getAttribute("BATCH_RUNNING"));
            return;
        }
        application.setAttribute("BATCH_RUNNING", today("yyyy-MM-dd HH:mm:ss"));
        Calendar calPrev = Calendar.getInstance();
        calPrev.add(Calendar.MONTH, -1);
        String strCloseYm = new SimpleDateFormat("yyyyMM").format(calPrev.getTime());
        StringBuffer sbRes = new StringBuffer();
        Connection conn = null;
        try {
            conn = getConn();
            loadCodeCache(true);
            sbRes.append(runArrearsNotice(conn)).append("\n");
            sbRes.append("만료 견적 " + expireQuotes(conn) + "건 종결\n");
            sbRes.append(runMonthClose(conn, strCloseYm)).append("\n");
            // 결과를 공지사항에도 남긴다 (영업팀이 공지에서 보고 싶다고 해서)
            execUpdate(conn, "INSERT INTO TB_NOTICE (TITLE, CONTENT, WRITER_ID, VIEW_CNT, TOP_YN, REG_DT) VALUES (?, ?, 'BATCH', 0, 'N', NOW())",
                new Object[] { "[배치] " + today("yyyy-MM-dd") + " 실행 결과", sbRes.toString() });
            out.clear();
            response.setContentType("text/plain; charset=UTF-8");
            out.print(sbRes.toString());
        } catch (Exception e) {
            out.print("ERROR " + e.getMessage());
        } finally {
            application.removeAttribute("BATCH_RUNNING");
            closeAll(null, null, conn);
        }
        return;
    //  } else if ("oldSalesReport".equals(cmd)) {
    //      // 2021.03 첫 버전 매출 리포트 (TB_ORDER 만 읽음).  salesReport 로 바꾸면서 막았다 - 지우지 말라고 해서 그냥 둠
    //      Connection conn = getConn();
    //      ResultSet rs = conn.createStatement().executeQuery("SELECT CUST_ID, SUM(ORDER_AMT) FROM TB_ORDER GROUP BY CUST_ID");
    //      while (rs.next()) { out.println(rs.getString(1) + "," + rs.getLong(2)); }
    }   // ---- [처리 전용 cmd] 끝.  여기까지 안 걸린 cmd 는 아래 화면 cmd 로 내려간다
%>
<!DOCTYPE html>
<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8"/>
<meta http-equiv="X-UA-Compatible" content="IE=edge"/>
<title>SMS 영업관리시스템</title>
<style type="text/css">
body { font-family: "맑은 고딕", Dotum, sans-serif; font-size: 12px; color: #333; margin: 0; background: #f4f5f7; }
#topbar { background: #2c3e50; padding: 8px 14px; color: #fff; }
#topbar a { color: #ecf0f1; margin-right: 10px; text-decoration: none; }
#topbar .logo { font-weight: bold; margin-right: 20px; }
#topbar .who { float: right; }
#wrap { padding: 14px 18px; }
h2 { font-size: 16px; margin: 4px 0 10px 0; }
h3 { font-size: 13px; margin: 14px 0 6px 0; }
table.list { border-collapse: collapse; width: 100%; background: #fff; }
table.list th { background: #e9ecef; border: 1px solid #ccc; padding: 5px; }
table.list td { border: 1px solid #ddd; padding: 4px 6px; }
table.list td.num { text-align: right; }
.searchbox { background: #fff; border: 1px solid #ddd; padding: 8px; margin-bottom: 8px; }
.formtbl { border-collapse: collapse; background: #fff; }
.formtbl th { background: #f1f3f5; border: 1px solid #ccc; padding: 5px 10px; text-align: left; }
.formtbl td { border: 1px solid #ddd; padding: 4px 8px; }
.btn { padding: 3px 10px; border: 1px solid #999; background: #f8f8f8; cursor: pointer; }
.btn-main { background: #2980b9; color: #fff; border-color: #2471a3; }
.err { color: #c0392b; }
.warn { color: #d35400; font-weight: bold; }
.cards div { display: inline-block; width: 22%; background: #fff; border: 1px solid #ddd; padding: 10px; margin-right: 1%; }
.cards b { display: block; font-size: 18px; margin-top: 4px; }
.loginbox { width: 320px; margin: 90px auto; background: #fff; padding: 24px; border: 1px solid #ccc; }
.paging { text-align: center; margin: 10px 0; }
</style>
<script type="text/javascript">
var thisPage = '<%= thisPage %>';
var authCd = '<%= esc(authCd) %>';

// 같은 JSP 의 cmd 를 부르는 공통 함수 (2016.03 홍길동).  답은 JSON ({ok:true/false, msg:...})
function callCmd(cmd, params, onOk, onFail) {
    var xhr = new XMLHttpRequest();
    var body = 'cmd=' + encodeURIComponent(cmd);
    for (var k in params) {
        if (params[k] === undefined || params[k] === null) continue;
        if (params[k] instanceof Array) {
            for (var i = 0; i < params[k].length; i++) body += '&' + k + '=' + encodeURIComponent(params[k][i]);
        } else {
            body += '&' + k + '=' + encodeURIComponent(params[k]);
        }
    }
    xhr.open('POST', thisPage, true);
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded; charset=UTF-8');
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.onreadystatechange = function() {
        if (xhr.readyState != 4) return;
        if (xhr.status == 401) {
            alert('로그인이 끝났습니다. 다시 로그인하세요.');
            location.href = thisPage + '?cmd=login';
            return;
        }
        var res = null;
        try { res = JSON.parse(xhr.responseText); } catch (e) { alert('서버 응답 오류'); return; }
        if (res.ok === false) {
            if (onFail) onFail(res); else alert(res.msg);
            return;
        }
        if (onOk) onOk(res);
    };
    xhr.send(body);
}

// 폼 값을 {이름: 값} 으로 (같은 이름이 여러 개면 배열)
function formToParams(form) {
    var p = {};
    for (var i = 0; i < form.elements.length; i++) {
        var el = form.elements[i];
        if (!el.name || el.disabled) continue;
        if ((el.type == 'checkbox' || el.type == 'radio') && !el.checked) continue;
        if (p[el.name] === undefined) p[el.name] = el.value;
        else if (p[el.name] instanceof Array) p[el.name].push(el.value);
        else p[el.name] = [p[el.name], el.value];
    }
    return p;
}

function goCmd(cmd, qs) { location.href = thisPage + '?cmd=' + cmd + (qs ? '&' + qs : ''); }
function fmtNum(n) { return String(Math.round(Number(n) || 0)).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
function numOnly(el) { el.value = el.value.replace(/[^0-9]/g, ''); }
function chkDate(v) { return /^\d{4}-\d{2}-\d{2}$/.test(v); }

// 품목 입력 그리드 (견적 · 수주 화면이 같이 쓴다).  화면에서 prodOpts(<option> 문자열)를 먼저 정의해 둘 것
function addItemRow(pid, qty) {
    var tr = document.createElement('tr');
    tr.innerHTML = '<td><select name="productId" onchange="onProdSelect(this)"><option value="">선택</option>' + prodOpts + '</select></td>'
        + '<td><input type="text" name="qty" size="4" value="' + (qty || 1) + '" onkeyup="numOnly(this);calcItems()"/></td><td class="num">0</td><td class="num">0</td>';
    document.getElementById('tblItem').getElementsByTagName('tbody')[0].appendChild(tr);
    if (pid) { tr.getElementsByTagName('select')[0].value = pid; onProdSelect(tr.getElementsByTagName('select')[0]); }
}
// 제품을 고르면 기준일(오늘) 단가를 제품 쪽 cmd 로 읽어 온다
function onProdSelect(sel) {
    var tr = sel.parentNode.parentNode;
    if (sel.value == '') return;
    callCmd('priceInfo', { productId: sel.value }, function(res) {
        tr.cells[2].innerHTML = fmtNum(res.unitPrice);
        tr.cells[2].setAttribute('data-p', res.unitPrice);
        calcItems();
    });
}
function calcItems() {
    var rows = document.getElementById('tblItem').getElementsByTagName('tbody')[0].rows, total = 0;
    for (var i = 0; i < rows.length; i++) {
        var amt = Number(rows[i].cells[2].getAttribute('data-p') || 0) * Number(rows[i].cells[1].getElementsByTagName('input')[0].value || 0);
        rows[i].cells[3].innerHTML = fmtNum(amt);
        total += amt;
    }
    document.getElementById('bTotal').innerHTML = fmtNum(total);
}
// 거래처 찾기 : 거래처 쪽 목록 cmd 를 불러 링크로 보여 준다 (pickFn = 눌렀을 때 부를 함수)
function findCust(wordId, listId, pickFn) {
    callCmd('custListData', { searchWord: document.getElementById(wordId).value, pageSize: 10 }, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length; i++) {
            html += '<a href="javascript:' + pickFn + '(\'' + res.list[i].custId + '\', \'' + res.list[i].custNm + '\')">' + res.list[i].custNm + '</a> ';
        }
        document.getElementById(listId).innerHTML = html;
    });
}

// 필수 입력 검사 : names = ['custNm:거래처명', ...]
function chkRequired(form, names) {
    for (var i = 0; i < names.length; i++) {
        var kv = names[i].split(':');
        if (form[kv[0]].value.replace(/\s/g, '') == '') {
            alert(kv[1] + ' 을(를) 입력하세요.');
            form[kv[0]].focus();
            return false;
        }
    }
    return true;
}
</script>
</head>
<body>
<% if (loginUser != null) { %>
<div id="topbar">
    <span class="logo">SMS 영업관리</span>
    <a href="javascript:goCmd('main')">대시보드</a>
    <a href="javascript:goCmd('custList')">거래처</a>
    <a href="javascript:goCmd('opptyList')">영업기회</a>
    <a href="javascript:goCmd('quoteList')">견적</a>
    <a href="javascript:goCmd('orderList')">수주</a>
    <a href="javascript:goCmd('contractList')">계약</a>
    <a href="javascript:goCmd('billList')">청구</a>
    <a href="javascript:goCmd('collectList')">수금</a>
    <a href="javascript:goCmd('arrearsList')">미수</a>
    <a href="javascript:goCmd('prodList')">제품</a>
    <a href="javascript:goCmd('salesReport')">리포트</a>
    <a href="javascript:goCmd('noticeList')">공지</a>
    <%-- 2018.11 메뉴에서 뺌 (영업팀이 안 쓴다고 해서) : <a href="javascript:goCmd('custHist')">거래처 이력</a> --%>
<% if ("ADMIN".equals(authCd)) { %>
    <a href="javascript:goCmd('codeList')">공통코드</a>
<% } %>
    <span class="who"><%= esc(loginNm) %> (<%= esc(authCd) %>) <a href="<%= thisPage %>?cmd=logout">로그아웃</a></span>
</div>
<% } %>
<div id="wrap">
<%
    // ================================================================
    //  [화면 cmd]  cmd 별 화면.  목록 데이터는 화면 열 때 여기서 바로 읽거나, 화면의 JS 가 위의 처리 cmd 를 부른다
    // ================================================================
    if ("login".equals(cmd)) {
%>
<div class="loginbox">
    <h2>SMS 영업관리시스템</h2>
    <% if ("1".equals(request.getParameter("err"))) { %><p class="err">아이디 또는 비밀번호가 일치하지 않습니다.</p><% } %>
    <% if ("2".equals(request.getParameter("err"))) { %><p class="err">로그인 중 오류가 났습니다. 관리자에게 문의하세요.</p><% } %>
    <form name="frmLogin" method="post" action="<%= thisPage %>" onsubmit="return chkLogin(this);">
        <input type="hidden" name="cmd" value="doLogin"/>
        <p>아이디 <input type="text" name="userId" maxlength="20"/></p>
        <p>비밀번호 <input type="password" name="passwd" maxlength="30"/></p>
        <p><button type="submit" class="btn btn-main">로그인</button></p>
    </form>
</div>
<script type="text/javascript">
function chkLogin(f) {
    if (f.userId.value == '') { alert('아이디를 입력하세요.'); f.userId.focus(); return false; }
    if (f.passwd.value == '') { alert('비밀번호를 입력하세요.'); f.passwd.focus(); return false; }
    return true;
}
document.frmLogin.userId.focus();
</script>
<%
    } else if ("main".equals(cmd)) {
        // 대시보드 : 이번 달 수주와 미수 건수는 화면을 열 때 바로 읽는다 (2021.03 김철수)
        String strMonth = today("yyyy-MM");
        long lMonthOrderAmt = 0L, lArrearsCnt = 0L;
        Connection conn = null;
        try {
            conn = getConn();
            lMonthOrderAmt = queryLong(conn, "SELECT IFNULL(SUM(ORDER_AMT), 0) FROM TB_ORDER WHERE DATE_FORMAT(ORDER_DT, '%Y-%m') = ? AND ORDER_STATUS != '취소'",
                    new Object[] { strMonth }, 0L);
            lArrearsCnt = queryLong(conn, "SELECT COUNT(*) FROM TB_BILL B WHERE B.ISSUE_STATUS = '10' "
                    + "AND B.TOTAL_AMT > IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0)", null, 0L);
        } catch (Exception e) {
            printErr(out, "대시보드 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>대시보드 (<%= strMonth %>)</h2>
<div class="cards">
    <div>이번 달 수주<b><%= fmtAmt(lMonthOrderAmt) %>원</b></div>
    <div>미수 청구<b><%= lArrearsCnt %>건</b></div>
    <div>로그인<b><%= esc(loginNm) %></b></div>
</div>
<h3>최근 등록 거래처</h3><ul id="ulCust"></ul>
<h3>최근 수주</h3><ul id="ulOrder"></ul>
<h3>30일 넘은 미수</h3><ul id="ulArrears"></ul>
<script type="text/javascript">
window.onload = function() { loadCust(); loadOrder(); loadArrears(); };

// 아래 세 함수는 각각 거래처 · 수주 · 수금 쪽 cmd 를 부른다
function loadCust() {
    callCmd('custListData', { pageNo: 1, pageSize: 5, sortCol: 'C.REG_DT', sortDir: 'DESC' }, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length; i++) html += '<li>' + res.list[i].custNm + ' (' + res.list[i].custGradeNm + ')</li>';
        document.getElementById('ulCust').innerHTML = html;
    });
}
function loadOrder() {
    callCmd('orderListData', { pageNo: 1, pageSize: 5 }, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length; i++) {
            var r = res.list[i];
            html += '<li>' + r.orderDt + ' ' + r.custNm + ' ' + fmtNum(r.orderAmt) + '원 [' + r.orderStatus + ']</li>';
        }
        document.getElementById('ulOrder').innerHTML = html;
    });
}
function loadArrears() {
    callCmd('arrearsData', { overdueDays: 30 }, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length && i < 5; i++) {
            html += '<li>' + res.list[i].custNm + ' ' + fmtNum(res.list[i].arrearsAmt) + '원 (' + res.list[i].overdueDays + '일)</li>';
        }
        document.getElementById('ulArrears').innerHTML = html;
    });
}
</script>
<%
    } else if ("noticeList".equals(cmd)) {
        // 공지 목록 (TB_NOTICE) : 최근 50건
        List<HashMap<String, Object>> noticeRows = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            noticeRows = queryList(conn, "SELECT NOTICE_ID, TITLE, WRITER_ID, VIEW_CNT, TOP_YN, REG_DT FROM TB_NOTICE ORDER BY TOP_YN DESC, NOTICE_ID DESC LIMIT 50", null);
        } catch (Exception e) {
            printErr(out, "공지 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>공지사항</h2>
<table class="list">
    <thead><tr><th>번호</th><th>제목</th><th>작성자</th><th>조회</th><th>등록일</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> n : noticeRows) { %>
        <tr><td><%= n.get("NOTICE_ID") %></td>
            <td><a href="javascript:goCmd('noticeView', 'noticeId=<%= n.get("NOTICE_ID") %>')"><%= "Y".equals(n.get("TOP_YN")) ? "[필독] " : "" %><%= esc(n.get("TITLE")) %></a></td>
            <td><%= esc(n.get("WRITER_ID")) %></td><td><%= n.get("VIEW_CNT") %></td><td><%= n.get("REG_DT") %></td></tr>
<% } %>
    </tbody>
</table>
<% if (!"USER".equals(authCd)) { %>
<h3>공지 등록</h3>
<form name="frmNotice" onsubmit="return false;">
    <table class="formtbl">
        <tr><th>제목</th><td><input type="text" name="title" size="60" maxlength="200"/></td></tr>
        <tr><th>내용</th><td><textarea name="content" cols="60" rows="5"></textarea></td></tr>
        <tr><th>상단 고정</th><td><input type="checkbox" name="topYn" value="Y"/> 필독 공지</td></tr>
    </table>
    <p><button type="button" class="btn btn-main" onclick="fnNoticeSave()">등록</button></p>
</form>
<% } %>
<script type="text/javascript">
function fnNoticeSave() {
    var f = document.frmNotice;
    if (!chkRequired(f, ['title:제목', 'content:내용'])) return;
    callCmd('noticeSave', formToParams(f), function() { goCmd('noticeList'); });
}
</script>
<%
    } else if ("noticeView".equals(cmd)) {
        // 공지 보기 : 열 때마다 조회수를 올린다 (조회 화면에서 바로 UPDATE).  2016.04 에 만든 화면이라 직접 JDBC
        HashMap<String, Object> notice = null;
        String strNoticeId = request.getParameter("noticeId");
        Connection conn = null;
        Statement st = null;
        ResultSet rs = null;
        try {
            conn = getConn();
            st = conn.createStatement();
            st.executeUpdate("UPDATE TB_NOTICE SET VIEW_CNT = VIEW_CNT + 1 WHERE NOTICE_ID = " + strNoticeId);
            rs = st.executeQuery("SELECT NOTICE_ID, TITLE, CONTENT, WRITER_ID, VIEW_CNT, REG_DT FROM TB_NOTICE WHERE NOTICE_ID = " + strNoticeId);
            if (rs.next()) {
                notice = new HashMap<String, Object>();
                for (String k : new String[] { "NOTICE_ID", "TITLE", "CONTENT", "WRITER_ID", "VIEW_CNT", "REG_DT" }) {
                    notice.put(k, rs.getObject(k));
                }
            }
        } catch (Exception e) {
            printErr(out, "공지 조회", e);
        } finally {
            closeAll(rs, st, conn);
        }
        if (notice == null) {
%>
<p class="err">공지를 찾을 수 없습니다.</p>
<%      } else { %>
<h2><%= esc(notice.get("TITLE")) %></h2>
<p><small>작성자 <%= esc(notice.get("WRITER_ID")) %> · 조회 <%= notice.get("VIEW_CNT") %> · <%= notice.get("REG_DT") %></small></p>
<div style="background:#fff;padding:12px;border:1px solid #ddd;white-space:pre-wrap"><%= esc(notice.get("CONTENT")) %></div>
<p><button type="button" class="btn" onclick="goCmd('noticeList')">목록</button></p>
<%      }
    } else if ("codeList".equals(cmd)) {
        // 공통코드 관리 (관리자) : TB_CODE 를 직접 읽는다.  고친 뒤에는 [캐시 갱신]
        List<HashMap<String, Object>> codeRows = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            codeRows = queryList(conn, "SELECT GRP_CD, CD, CD_NM, SORT_ORD, USE_YN FROM TB_CODE ORDER BY GRP_CD, SORT_ORD, CD", null);
        } catch (Exception e) {
            printErr(out, "공통코드 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>공통코드 관리</h2>
<form name="frmCode" onsubmit="return false;" class="searchbox">
    그룹 <input type="text" name="grpCd" size="14"/> 코드 <input type="text" name="cd" size="8"/> 코드명 <input type="text" name="cdNm" size="16"/>
    순서 <input type="text" name="sortOrd" size="3" value="0"/> 사용 <select name="useYn"><option value="Y">Y</option><option value="N">N</option></select>
    <button type="button" class="btn btn-main" onclick="fnCodeSave()">저장</button>
    <button type="button" class="btn" onclick="fnReload()">캐시 갱신</button>
    <a href="<%= thisPage %>?cmd=masterExport&tbl=CODE&orderBy=GRP_CD,SORT_ORD">엑셀</a>
</form>
<table class="list">
    <thead><tr><th>그룹</th><th>코드</th><th>코드명</th><th>순서</th><th>사용</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> c : codeRows) { %>
        <tr><td><%= esc(c.get("GRP_CD")) %></td><td><%= esc(c.get("CD")) %></td><td><%= esc(c.get("CD_NM")) %></td><td><%= c.get("SORT_ORD") %></td><td><%= c.get("USE_YN") %></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnCodeSave() {
    if (!chkRequired(document.frmCode, ['grpCd:그룹', 'cd:코드', 'cdNm:코드명'])) return;
    callCmd('codeSave', formToParams(document.frmCode), function() { goCmd('codeList'); });
}
function fnReload() { callCmd('cacheReload', {}, function() { alert('캐시를 갱신했습니다. (이 서버만)'); }); }
</script>
<%
    } else if ("custList".equals(cmd)) {
%>
<h2>거래처 관리</h2>
<form id="frmSearch" onsubmit="return false;" class="searchbox">
    거래처명 · 대표자 · 사업자번호 <input type="text" name="searchWord" id="searchWord"/>
    <%= codeSelect("creditStatus", "CREDIT_STATUS", "", "여신상태 전체") %>
    <button type="button" class="btn btn-main" onclick="fnSearch(1)">조회</button>
    <button type="button" class="btn" onclick="goCmd('custForm')">신규 등록</button>
    <a href="<%= thisPage %>?cmd=masterExport&tbl=CUSTOMER&orderBy=CUST_NM">엑셀</a>
</form>
<table class="list">
    <thead><tr><th>거래처명</th><th>사업자번호</th><th>대표자</th><th>등급</th><th>여신상태</th><th>담당자</th><th>관리</th></tr></thead>
    <tbody id="tbodyCust"></tbody>
</table>
<div class="paging" id="divPaging"></div>
<script type="text/javascript">
var curPage = 1;
window.onload = function() { fnSearch(1); };

function fnSearch(pageNo) {
    curPage = pageNo;
    var p = formToParams(document.getElementById('frmSearch'));
    p.pageNo = pageNo;
    p.pageSize = 20;
    callCmd('custListData', p, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length; i++) {
            var r = res.list[i];
            html += '<tr><td><a href="javascript:goCmd(\'custForm\', \'custId=' + r.custId + '\')">' + r.custNm + '</a></td>';
            html += '<td>' + r.bizNo + '</td><td>' + r.ceoNm + '</td><td>' + r.custGradeNm + '</td>';
            // 여신상태 03(연체) 이면 빨갛게 - 코드값을 화면에서도 직접 비교한다
            html += '<td class="' + (r.creditStatus == '03' ? 'err' : '') + '">' + r.creditStatusNm + '</td><td>' + r.chargeUserNm + '</td>';
            html += '<td><a href="javascript:fnDelete(\'' + r.custId + '\')">사용중지</a></td></tr>';
        }
        document.getElementById('tbodyCust').innerHTML = html;
        document.getElementById('divPaging').innerHTML = '총 ' + res.totalCnt + '건';
    });
}

function fnDelete(custId) {
    if (!confirm('사용중지하시겠습니까? (접수 상태 수주와 발행 전 청구도 같이 취소됩니다)')) return;
    callCmd('custDelete', { custId: custId }, function(res) {
        alert('수주 ' + res.canceledOrder + '건 · 청구 ' + res.canceledBill + '건을 같이 취소했습니다.');
        fnSearch(curPage);
    });
}
</script>
<%
    } else if ("custForm".equals(cmd)) {
        // 거래처 등록 / 수정 : custId 가 있으면 수정
        String strEditId = nvl(request.getParameter("custId"), "");
        HashMap<String, Object> cust = null;
        List<HashMap<String, Object>> chargeRows = new ArrayList<HashMap<String, Object>>();
        long lCustArrears = 0L;
        Connection conn = null;
        try {
            conn = getConn();
            if (strEditId.length() > 0) {
                cust = queryOne(conn, "SELECT CUST_ID, CUST_NM, BIZ_NO, CEO_NM, ADDR, ADDR_DTL, TEL_NO, CUST_GRADE, CREDIT_STATUS, CREDIT_LIMIT, CHARGE_USER_ID, LAST_NOTICE_DT "
                        + "FROM TB_CUSTOMER WHERE CUST_ID = ?", new Object[] { strEditId });
                lCustArrears = custArrearsAmt(conn, strEditId);
            }
            chargeRows = queryList(conn, "SELECT USER_ID, USER_NM FROM TB_USER WHERE USE_YN = 'Y' ORDER BY USER_NM", null);
        } catch (Exception e) {
            printErr(out, "거래처 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
        boolean bEdit = cust != null;
%>
<h2>거래처 <%= bEdit ? "수정" : "등록" %></h2>
<form name="frmCust" onsubmit="return false;">
    <input type="hidden" name="custId" value="<%= bEdit ? esc(cust.get("CUST_ID")) : "" %>"/>
    <table class="formtbl">
        <tr><th>거래처명 *</th><td><input type="text" name="custNm" size="30" value="<%= bEdit ? esc(cust.get("CUST_NM")) : "" %>"/></td>
            <th>사업자번호 *</th><td><input type="text" name="bizNo" size="14" maxlength="12" value="<%= bEdit ? esc(cust.get("BIZ_NO")) : "" %>"/></td></tr>
        <tr><th>대표자</th><td><input type="text" name="ceoNm" value="<%= bEdit ? esc(cust.get("CEO_NM")) : "" %>"/></td>
            <th>전화</th><td><input type="text" name="telNo" value="<%= bEdit ? esc(cust.get("TEL_NO")) : "" %>"/></td></tr>
        <tr><th>주소</th><td colspan="3"><input type="text" name="addr" size="50" value="<%= bEdit ? esc(cust.get("ADDR")) : "" %>"/>
            <input type="text" name="addrDtl" size="24" value="<%= bEdit ? esc(cust.get("ADDR_DTL")) : "" %>"/></td></tr>
        <tr><th>등급</th><td><%= codeSelect("custGrade", "CUST_GRADE", bEdit ? (String) cust.get("CUST_GRADE") : "C", null) %></td>
            <th>여신한도(원)</th><td><input type="text" name="creditLimit" size="14" onkeyup="numOnly(this)" value="<%= bEdit && cust.get("CREDIT_LIMIT") != null ? cust.get("CREDIT_LIMIT") : "" %>"/></td></tr>
        <tr><th>담당 사원</th><td><select name="chargeUserId">
<% for (HashMap<String, Object> u : chargeRows) { %>
            <option value="<%= u.get("USER_ID") %>"<%= bEdit && u.get("USER_ID").equals(cust.get("CHARGE_USER_ID")) || !bEdit && u.get("USER_ID").equals(loginId) ? " selected" : "" %>><%= esc(u.get("USER_NM")) %></option>
<% } %>
        </select></td>
            <th>여신상태</th><td><%= bEdit ? codeName("CREDIT_STATUS", (String) cust.get("CREDIT_STATUS")) + " / 현재 미수 " + fmtAmt(lCustArrears) + "원" : "신규(정상)" %></td></tr>
<% if (!bEdit) { %>
        <tr><th>담당자명</th><td><input type="text" name="contactNm"/></td><th>이메일</th><td><input type="text" name="contactEmail" size="24"/></td></tr>
        <tr><th>부서 · 직위</th><td><input type="text" name="contactDept" size="10"/> <input type="text" name="contactPos" size="8"/></td><th>휴대전화</th><td><input type="text" name="contactMobile"/></td></tr>
<% } %>
    </table>
    <p><button type="button" class="btn btn-main" onclick="fnSave()">저장</button> <button type="button" class="btn" onclick="goCmd('custList')">목록</button></p>
</form>
<script type="text/javascript">
function fnSave() {
    var f = document.frmCust;
    if (!chkRequired(f, ['custNm:거래처명', 'bizNo:사업자번호'])) return;
    callCmd('custSave', formToParams(f), function(res) { alert('저장했습니다.'); goCmd('custList'); });
}
</script>
<%
    } else if ("prodList".equals(cmd)) {
        // 제품 · 기간별 단가 관리 : 제품 목록을 읽고, 단가 입력은 priceSave 로 보낸다
        List<HashMap<String, Object>> prodRows = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            prodRows = queryList(conn, "SELECT PRODUCT_ID, PRODUCT_NM, PRODUCT_TYPE, UNIT_CD, UNIT_PRICE FROM TB_PRODUCT WHERE USE_YN = 'Y' ORDER BY PRODUCT_NM", null);
        } catch (Exception e) {
            printErr(out, "제품 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>제품 · 단가 관리</h2>
<form name="frmProd" onsubmit="return false;" class="searchbox">
    <input type="hidden" name="productId" value=""/>
    제품명 <input type="text" name="productNm" size="20"/> 유형 <input type="text" name="productType" size="8"/>
    단위 <input type="text" name="unitCd" size="4"/> 기본단가 <input type="text" name="unitPrice" size="10" onkeyup="numOnly(this)"/>
    <button type="button" class="btn btn-main" onclick="fnProdSave()">저장</button>
    <a href="<%= thisPage %>?cmd=masterExport&tbl=PRODUCT&orderBy=PRODUCT_NM">엑셀</a>
</form>
<table class="list">
    <thead><tr><th>제품</th><th>유형</th><th>단위</th><th>기본단가</th><th>선택</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> p : prodRows) { %>
        <tr><td><%= esc(p.get("PRODUCT_NM")) %></td><td><%= esc(p.get("PRODUCT_TYPE")) %></td><td><%= esc(p.get("UNIT_CD")) %></td>
            <td class="num"><%= fmtAmt(p.get("UNIT_PRICE")) %></td>
            <td><a href="javascript:fnPick('<%= p.get("PRODUCT_ID") %>', '<%= jq(p.get("PRODUCT_NM")) %>')">단가 입력</a></td></tr>
<% } %>
    </tbody>
</table>
<h3>기간별 단가</h3>
<form name="frmPrice" onsubmit="return false;" class="searchbox">
    <input type="hidden" name="productId" value=""/>
    제품 <b id="bPickNm">(위 표에서 선택)</b> 등급 <%= codeSelect("custGrade", "CUST_GRADE", "", "공통") %>
    단가 <input type="text" name="unitPrice" size="10" onkeyup="numOnly(this)"/>
    적용 <input type="text" name="applyFromDt" size="10" placeholder="yyyy-mm-dd"/> ~ <input type="text" name="applyToDt" size="10" placeholder="yyyy-mm-dd"/>
    <button type="button" class="btn btn-main" onclick="fnPriceSave()">추가</button>
</form>
<script type="text/javascript">
function fnPick(id, nm) {
    document.frmPrice.productId.value = id;
    document.getElementById('bPickNm').innerHTML = nm;
}
function fnProdSave() {
    var f = document.frmProd;
    if (!chkRequired(f, ['productNm:제품명', 'unitPrice:기본단가'])) return;
    callCmd('prodSave', formToParams(f), function() { goCmd('prodList'); });
}
function fnPriceSave() {
    var f = document.frmPrice;
    if (f.productId.value == '') { alert('위 표에서 제품을 먼저 선택하세요.'); return; }
    if (!chkDate(f.applyFromDt.value) || !chkDate(f.applyToDt.value)) { alert('적용 기간을 yyyy-mm-dd 로 입력하세요.'); return; }
    callCmd('priceSave', formToParams(f), function() { goCmd('prodList'); });
}
</script>
<%
    } else if ("opptyList".equals(cmd)) {
        // 영업기회 : 거래처 이름은 거래처 표를 조인해서 읽는다 (2016.05 화면 - 조건 값을 SQL 에 바로 붙였다)
        List<HashMap<String, Object>> opptyRows = new ArrayList<HashMap<String, Object>>();
        List<HashMap<String, Object>> opptyCustRows = new ArrayList<HashMap<String, Object>>();
        StringBuffer sbOpptyWhere = new StringBuffer(" WHERE 1 = 1");
        if (nvl(request.getParameter("stageCd"), "").length() > 0) {
            sbOpptyWhere.append(" AND O.STAGE_CD = '" + request.getParameter("stageCd") + "'");
        }
        if ("USER".equals(authCd)) {                        // 영업사원은 본인 담당만
            sbOpptyWhere.append(" AND O.CHARGE_USER_ID = '" + loginId + "'");
        }
        Connection conn = null;
        try {
            conn = getConn();
            opptyRows = queryList(conn, "SELECT O.OPPTY_ID, O.CUST_ID, C.CUST_NM, O.OPPTY_NM, O.STAGE_CD, O.EXPECT_AMT, O.EXPECT_CLOSE_DT, O.STATUS_CD "
                    + "FROM TB_OPPTY O LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID" + sbOpptyWhere + " ORDER BY O.EXPECT_CLOSE_DT, O.OPPTY_ID", null);
            opptyCustRows = queryList(conn, "SELECT CUST_ID, CUST_NM FROM TB_CUSTOMER WHERE USE_YN = 'Y' ORDER BY CUST_NM", null);
        } catch (Exception e) {
            printErr(out, "영업기회 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>영업기회</h2>
<form name="frmOppty" onsubmit="return false;" class="searchbox">
    거래처 <select name="custId"><% for (HashMap<String, Object> oc : opptyCustRows) { %><option value="<%= oc.get("CUST_ID") %>"><%= esc(oc.get("CUST_NM")) %></option><% } %></select>
    건명 <input type="text" name="opptyNm" size="24"/> 예상금액 <input type="text" name="expectAmt" size="12" onkeyup="numOnly(this)"/>
    예상 종료일 <input type="text" name="expectCloseDt" size="10" placeholder="yyyy-mm-dd"/>
    <button type="button" class="btn btn-main" onclick="fnOpptySave()">등록</button>
</form>
<table class="list">
    <thead><tr><th>거래처</th><th>건명</th><th>단계</th><th>예상금액</th><th>예상 종료일</th><th>견적</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> o : opptyRows) { %>
        <tr><td><%= esc(o.get("CUST_NM")) %></td><td><%= esc(o.get("OPPTY_NM")) %></td>
            <td><select onchange="fnStage('<%= o.get("OPPTY_ID") %>', this.value)">
<% for (String[] stg : new String[][] { {"10", "발굴"}, {"20", "제안"}, {"30", "협상"}, {"40", "수주"}, {"90", "실주"} }) { %>
                <option value="<%= stg[0] %>"<%= stg[0].equals(o.get("STAGE_CD")) ? " selected" : "" %>><%= stg[1] %></option>
<% } %></select></td>
            <td class="num"><%= fmtAmt(o.get("EXPECT_AMT")) %></td><td><%= o.get("EXPECT_CLOSE_DT") == null ? "" : o.get("EXPECT_CLOSE_DT") %></td>
            <td><a href="javascript:goCmd('quoteForm', 'opptyId=<%= o.get("OPPTY_ID") %>&custId=<%= o.get("CUST_ID") %>')">견적 작성</a></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnOpptySave() {
    var f = document.frmOppty;
    if (!chkRequired(f, ['opptyNm:건명'])) return;
    callCmd('opptySave', formToParams(f), function() { goCmd('opptyList'); });
}
function fnStage(opptyId, stageCd) {
    callCmd('opptyStage', { opptyId: opptyId, stageCd: stageCd }, function() { goCmd('opptyList'); });
}
</script>
<%
    } else if ("quoteList".equals(cmd)) {
        // 견적 목록 : 거래처 이름은 거래처 표를 조인해서 읽는다 (2016.06 화면 - 조건 값을 SQL 에 바로 붙였다)
        List<HashMap<String, Object>> quoteRows = new ArrayList<HashMap<String, Object>>();
        String strQuoteWhere = "USER".equals(authCd) ? " WHERE C.CHARGE_USER_ID = '" + loginId + "'" : "";     // 영업사원은 본인 담당 거래처만
        Connection conn = null;
        try {
            conn = getConn();
            quoteRows = queryList(conn, "SELECT Q.QUOTE_ID, Q.CUST_ID, C.CUST_NM, Q.QUOTE_NM, Q.QUOTE_DT, Q.VALID_DT, Q.TOTAL_AMT, Q.STATUS_CD "
                    + "FROM TB_QUOTE Q LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = Q.CUST_ID" + strQuoteWhere
                    + " ORDER BY Q.QUOTE_DT DESC, Q.QUOTE_ID DESC LIMIT 100", null);
        } catch (Exception e) {
            printErr(out, "견적 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>견적</h2>
<p><button type="button" class="btn btn-main" onclick="goCmd('quoteForm')">견적 작성</button></p>
<table class="list">
    <thead><tr><th>견적번호</th><th>거래처</th><th>견적명</th><th>견적일</th><th>유효기한</th><th>금액</th><th>상태</th><th>관리</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> q : quoteRows) { String st = (String) q.get("STATUS_CD"); %>
        <tr><td><%= q.get("QUOTE_ID") %></td><td><%= esc(q.get("CUST_NM")) %></td><td><%= esc(q.get("QUOTE_NM")) %></td><td><%= q.get("QUOTE_DT") %></td>
            <td><%= q.get("VALID_DT") %></td><td class="num"><%= fmtAmt(q.get("TOTAL_AMT")) %></td>
            <td><%= "10".equals(st) ? "작성" : "20".equals(st) ? "제출" : "종결" %></td>
            <td><% if ("10".equals(st)) { %><a href="javascript:fnSubmit('<%= q.get("QUOTE_ID") %>')">제출</a><% } %>
                <% if ("20".equals(st)) { %><a href="javascript:goCmd('orderForm', 'quoteId=<%= q.get("QUOTE_ID") %>')">수주 등록</a><% } %></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnSubmit(id) { callCmd('quoteSubmit', { quoteId: id }, function() { goCmd('quoteList'); }); }
</script>
<%
    } else if ("quoteForm".equals(cmd)) {
        // 견적 작성 : 영업기회 화면에서 넘어오면 opptyId · custId 가 같이 온다 (아래 hidden 으로 다시 넘긴다)
        String strQOpptyId = nvl(request.getParameter("opptyId"), "");
        String strQCustId = nvl(request.getParameter("custId"), "");
        String strQCustNm = "";
        List<HashMap<String, Object>> qProducts = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            if (strQCustId.length() > 0) {
                strQCustNm = (String) queryOne(conn, "SELECT CUST_NM FROM TB_CUSTOMER WHERE CUST_ID = ?", new Object[] { strQCustId }).get("CUST_NM");
            }
            qProducts = queryList(conn, "SELECT PRODUCT_ID, PRODUCT_NM FROM TB_PRODUCT WHERE USE_YN = 'Y' ORDER BY PRODUCT_NM", null);
        } catch (Exception e) {
            printErr(out, "견적 화면", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>견적 작성</h2>
<form name="frmQuote" onsubmit="return false;">
    <input type="hidden" name="opptyId" value="<%= esc(strQOpptyId) %>"/>
    <input type="hidden" name="custId" value="<%= esc(strQCustId) %>"/>
    <table class="formtbl">
        <tr><th>거래처</th><td><b id="bCustNm"><%= esc(strQCustNm) %></b> <input type="text" id="custWord" size="12"/>
            <button type="button" class="btn" onclick="findCust('custWord', 'spCustList', 'pickCust')">거래처 찾기</button> <span id="spCustList"></span></td></tr>
        <tr><th>견적명</th><td><input type="text" name="quoteNm" size="40"/></td></tr>
    </table>
    <h3>품목</h3>
    <table class="list" id="tblItem"><thead><tr><th>제품</th><th>수량</th><th>단가</th><th>금액</th></tr></thead><tbody></tbody></table>
    <p><button type="button" class="btn" onclick="addItemRow()">품목 추가</button> 합계 <b id="bTotal">0</b>원
       <button type="button" class="btn btn-main" onclick="fnSave()">저장</button></p>
</form>
<script type="text/javascript">
var prodOpts = '<% for (HashMap<String, Object> p : qProducts) { %><option value="<%= p.get("PRODUCT_ID") %>"><%= esc(p.get("PRODUCT_NM")) %></option><% } %>';
function pickCust(id, nm) {
    document.frmQuote.custId.value = id;
    document.getElementById('bCustNm').innerHTML = nm;
    document.getElementById('spCustList').innerHTML = '';
}
function fnSave() {
    var f = document.frmQuote;
    if (f.custId.value == '') { alert('거래처를 선택하세요.'); return; }
    if (!chkRequired(f, ['quoteNm:견적명'])) return;
    callCmd('quoteSave', formToParams(f), function(res) { alert('견적 ' + res.quoteId + ' 을(를) 저장했습니다.'); goCmd('quoteList'); });
}
addItemRow();
</script>
<%
    } else if ("orderList".equals(cmd)) {
%>
<h2>수주</h2>
<form id="frmSearch" onsubmit="return false;" class="searchbox">
    상태 <select name="orderStatus"><option value="">취소 제외 전체</option><option>접수</option><option>계약완료</option><option>청구완료</option><option>수금완료</option><option>취소</option></select>
    <button type="button" class="btn btn-main" onclick="fnSearch(1)">조회</button>
    <button type="button" class="btn" onclick="goCmd('orderForm')">수주 등록</button>
</form>
<table class="list">
    <thead><tr><th>수주번호</th><th>거래처</th><th>수주일</th><th>금액</th><th>상태</th><th>마감</th><th>관리</th></tr></thead>
    <tbody id="tbodyOrder"></tbody>
</table>
<div class="paging" id="divPaging"></div>
<script type="text/javascript">
var curPage = 1;
window.onload = function() { fnSearch(1); };

function fnSearch(pageNo) {
    curPage = pageNo;
    var p = formToParams(document.getElementById('frmSearch'));
    p.pageNo = pageNo;
    p.pageSize = 20;
    callCmd('orderListData', p, function(res) {
        var html = '';
        for (var i = 0; i < res.list.length; i++) {
            var r = res.list[i];
            html += '<tr><td><a href="javascript:goCmd(\'orderView\', \'orderId=' + r.orderId + '\')">' + r.orderId + '</a></td><td>' + r.custNm + '</td><td>' + r.orderDt + '</td>';
            html += '<td class="num">' + fmtNum(r.orderAmt) + '</td><td>' + r.orderStatus + '</td><td>' + r.closeYn + '</td><td>';
            // 접수 상태일 때만 [수주 완료] 를 보여 준다 (상태 문자열을 화면에서도 직접 비교한다)
            if (r.orderStatus == '접수') {
                html += '<a href="javascript:fnComplete(\'' + r.orderId + '\')">수주 완료</a>';
            }
            html += '</td></tr>';
        }
        document.getElementById('tbodyOrder').innerHTML = html;
        document.getElementById('divPaging').innerHTML = '총 ' + res.totalCnt + '건';
    });
}

function fnComplete(orderId) {
    if (!confirm('수주 완료 처리하면 계약과 청구(전자세금계산서)가 바로 만들어집니다. 진행할까요?')) return;
    callCmd('orderComplete', { orderId: orderId }, function(res) {
        alert('계약 ' + res.contractId + ' / 청구 ' + res.billId + ' 발행 완료');
        fnSearch(curPage);
    });
}
</script>
<%
    } else if ("orderForm".equals(cmd)) {
        // 수주 등록 : 견적 화면에서 넘어오면 quoteId 로 견적 · 견적 품목을 직접 읽어 채운다
        String strOQuoteId = nvl(request.getParameter("quoteId"), "");
        HashMap<String, Object> oQuote = null;
        List<HashMap<String, Object>> oQuoteItems = new ArrayList<HashMap<String, Object>>();
        List<HashMap<String, Object>> oProducts = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            if (strOQuoteId.length() > 0) {
                oQuote = queryOne(conn, "SELECT Q.QUOTE_ID, Q.CUST_ID, C.CUST_NM FROM TB_QUOTE Q INNER JOIN TB_CUSTOMER C ON C.CUST_ID = Q.CUST_ID "
                        + "WHERE Q.QUOTE_ID = ?", new Object[] { strOQuoteId });
                oQuoteItems = queryList(conn, "SELECT PRODUCT_ID, QTY FROM TB_QUOTE_ITEM WHERE QUOTE_ID = ? ORDER BY ITEM_SEQ", new Object[] { strOQuoteId });
            }
            oProducts = queryList(conn, "SELECT PRODUCT_ID, PRODUCT_NM FROM TB_PRODUCT WHERE USE_YN = 'Y' ORDER BY PRODUCT_NM", null);
        } catch (Exception e) {
            printErr(out, "수주 화면", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>수주 등록</h2>
<form name="frmOrder" onsubmit="return false;">
    <input type="hidden" name="quoteId" value="<%= esc(strOQuoteId) %>"/>
    <input type="hidden" name="custId" value="<%= oQuote == null ? "" : esc(oQuote.get("CUST_ID")) %>"/>
    <table class="formtbl">
        <tr><th>거래처</th><td><b id="bCustNm"><%= oQuote == null ? "" : esc(oQuote.get("CUST_NM")) %></b> <input type="text" id="custWord" size="12"/>
            <button type="button" class="btn" onclick="findCust('custWord', 'spCustList', 'pickCust')">거래처 찾기</button> <span id="spCustList"></span></td></tr>
        <tr><th>여신</th><td id="tdCredit">거래처를 고르면 여신한도와 미수가 표시됩니다.</td></tr>
    </table>
    <h3>품목</h3>
    <table class="list" id="tblItem"><thead><tr><th>제품</th><th>수량</th><th>단가</th><th>금액</th></tr></thead><tbody></tbody></table>
    <p><button type="button" class="btn" onclick="addItemRow()">품목 추가</button> 합계 <b id="bTotal">0</b>원
       <button type="button" class="btn btn-main" onclick="fnSave()">저장</button></p>
</form>
<script type="text/javascript">
var prodOpts = '<% for (HashMap<String, Object> p : oProducts) { %><option value="<%= p.get("PRODUCT_ID") %>"><%= esc(p.get("PRODUCT_NM")) %></option><% } %>';

// 거래처를 고르면 여신 정보를 거래처 쪽 cmd 로 읽어 온다
function pickCust(id, nm) {
    document.frmOrder.custId.value = id;
    document.getElementById('bCustNm').innerHTML = nm;
    document.getElementById('spCustList').innerHTML = '';
    callCmd('custCreditInfo', { custId: id }, function(res) {
        document.getElementById('tdCredit').innerHTML = '한도 ' + fmtNum(res.creditLimit) + '원 / 미수 ' + fmtNum(res.arrears) + '원 / 상태 ' + res.creditStatus
            + (res.creditStatus == '03' ? ' <span class="err">(연체 - 등록할 수 없음)</span>' : '');
    });
}
function fnSave() {
    var f = document.frmOrder;
    if (f.custId.value == '') { alert('거래처를 선택하세요.'); return; }
    callCmd('orderSave', formToParams(f), function(res) { alert('수주 ' + res.orderId + ' 을(를) 등록했습니다.'); goCmd('orderList'); });
}
<% for (HashMap<String, Object> qi : oQuoteItems) { %>addItemRow('<%= qi.get("PRODUCT_ID") %>', <%= qi.get("QTY") %>);
<% } %><% if (oQuoteItems.isEmpty()) { %>addItemRow();<% } %>
</script>
<%
    } else if ("orderView".equals(cmd)) {
        // 수주 상세 : 수주 · 품목 · 계약 · 청구 · 수금을 한 화면에서 전부 읽는다
        HashMap<String, Object> vOrder = null, vContract = null;
        List<HashMap<String, Object>> vItems = new ArrayList<HashMap<String, Object>>();
        List<HashMap<String, Object>> vBills = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            Object[] arrId = new Object[] { request.getParameter("orderId") };
            vOrder = queryOne(conn, "SELECT O.ORDER_ID, O.CUST_ID, C.CUST_NM, O.ORDER_DT, O.ORDER_AMT, O.ORDER_STATUS, O.CONTRACT_ID "
                    + "FROM TB_ORDER O LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID WHERE O.ORDER_ID = ?", arrId);
            vItems = queryList(conn, "SELECT I.ITEM_SEQ, P.PRODUCT_NM, I.QTY, I.UNIT_PRICE, I.AMT FROM TB_ORDER_ITEM I "
                    + "LEFT OUTER JOIN TB_PRODUCT P ON P.PRODUCT_ID = I.PRODUCT_ID WHERE I.ORDER_ID = ? ORDER BY I.ITEM_SEQ", arrId);
            vContract = queryOne(conn, "SELECT CONTRACT_ID, CONTRACT_NM, CONTRACT_AMT, START_DT, END_DT, STATUS_CD FROM TB_CONTRACT WHERE ORDER_ID = ?", arrId);
            vBills = queryList(conn, "SELECT B.BILL_ID, B.BILL_DT, B.TOTAL_AMT, B.ETAX_NO, B.ISSUE_STATUS, "
                    + "IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0) AS PAID_AMT "
                    + "FROM TB_BILL B WHERE B.ORDER_ID = ? ORDER BY B.BILL_DT", arrId);
        } catch (Exception e) {
            printErr(out, "수주 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
        if (vOrder != null) {
%>
<h2>수주 상세 <%= vOrder.get("ORDER_ID") %></h2>
<p>거래처 <b><%= esc(vOrder.get("CUST_NM")) %></b> · 수주일 <%= vOrder.get("ORDER_DT") %> · 금액 <%= fmtAmt(vOrder.get("ORDER_AMT")) %>원 · 상태 <b><%= vOrder.get("ORDER_STATUS") %></b></p>
<table class="list">
    <thead><tr><th>순번</th><th>제품</th><th>수량</th><th>단가</th><th>금액</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> it : vItems) { %>
        <tr><td><%= it.get("ITEM_SEQ") %></td><td><%= esc(it.get("PRODUCT_NM")) %></td><td><%= it.get("QTY") %></td>
            <td class="num"><%= fmtAmt(it.get("UNIT_PRICE")) %></td><td class="num"><%= fmtAmt(it.get("AMT")) %></td></tr>
<% } %>
    </tbody>
</table>
<h3>계약</h3>
<p><%= vContract == null ? "아직 계약이 없습니다." : esc(vContract.get("CONTRACT_NM")) + " / " + fmtAmt(vContract.get("CONTRACT_AMT")) + "원 / " + vContract.get("START_DT") + " ~ " + vContract.get("END_DT") %></p>
<h3>청구 · 수금</h3>
<% for (HashMap<String, Object> b : vBills) { %>
<p><%= b.get("BILL_ID") %> / <%= b.get("BILL_DT") %> / <%= fmtAmt(b.get("TOTAL_AMT")) %>원 / 승인번호 <%= esc(b.get("ETAX_NO")) %> / 수금 <%= fmtAmt(b.get("PAID_AMT")) %>원</p>
<% } %>
<p><button type="button" class="btn" onclick="goCmd('orderList')">목록</button></p>
<%      }
    } else if ("contractList".equals(cmd)) {
        // 계약 목록 : 금액 변경 · 계약서 첨부는 행마다 따로 처리한다 (2016.09 화면이라 직접 JDBC)
        List<HashMap<String, Object>> contractRows = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        Statement st = null;
        ResultSet rs = null;
        try {
            conn = getConn();
            st = conn.createStatement();
            String strCtSql = "SELECT T.CONTRACT_ID, T.ORDER_ID, C.CUST_NM, T.CONTRACT_NM, T.CONTRACT_AMT, T.START_DT, T.END_DT, T.STATUS_CD "
                    + "FROM TB_CONTRACT T LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = T.CUST_ID";
            if ("USER".equals(authCd)) {                    // 영업사원은 본인 담당 거래처만
                strCtSql += " WHERE C.CHARGE_USER_ID = '" + loginId + "'";
            }
            rs = st.executeQuery(strCtSql + " ORDER BY T.REG_DT DESC LIMIT 100");
            while (rs.next()) {
                HashMap<String, Object> row = new HashMap<String, Object>();
                for (String k : new String[] { "CONTRACT_ID", "ORDER_ID", "CUST_NM", "CONTRACT_NM", "CONTRACT_AMT", "START_DT", "END_DT", "STATUS_CD" }) {
                    row.put(k, rs.getObject(k));
                }
                contractRows.add(row);
            }
        } catch (Exception e) {
            printErr(out, "계약 조회", e);
        } finally {
            closeAll(rs, st, conn);
        }
%>
<h2>계약</h2>
<table class="list">
    <thead><tr><th>계약</th><th>거래처</th><th>기간</th><th>상태</th><th>금액 변경</th><th>계약서 첨부</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> t : contractRows) { %>
        <tr><td><%= esc(t.get("CONTRACT_NM")) %></td><td><%= esc(t.get("CUST_NM")) %></td><td><%= t.get("START_DT") %> ~ <%= t.get("END_DT") %></td>
            <td><%= "10".equals(t.get("STATUS_CD")) ? "진행" : "종료" %></td>
            <td><form onsubmit="return false;">
                <input type="hidden" name="contractId" value="<%= t.get("CONTRACT_ID") %>"/>
                <input type="hidden" name="orderId" value="<%= t.get("ORDER_ID") %>"/>
                <input type="text" name="contractAmt" size="12" value="<%= t.get("CONTRACT_AMT") %>" onkeyup="numOnly(this)"/>
                <button type="button" class="btn" onclick="fnAmt(this)">변경</button></form></td>
            <td><input type="file" id="file_<%= t.get("CONTRACT_ID") %>"/> <button type="button" class="btn" onclick="fnUpload('<%= t.get("CONTRACT_ID") %>')">첨부</button></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnAmt(btn) {
    callCmd('contractAmtUpdate', formToParams(btn.form), function() { alert('계약 금액과 수주 금액을 같이 바꿨습니다.'); goCmd('contractList'); });
}
function fnUpload(contractId) {
    var file = document.getElementById('file_' + contractId).files[0];
    if (!file) { alert('파일을 고르세요.'); return; }
    var xhr = new XMLHttpRequest();
    xhr.open('POST', thisPage + '?cmd=contractFile&contractId=' + contractId + '&fileName=' + encodeURIComponent(file.name), true);
    xhr.onload = function() { alert('첨부했습니다.'); };
    xhr.send(file);
}
</script>
<%
    } else if ("billList".equals(cmd)) {
        // 청구 목록 + 수기 발행 : 발행할 수주는 수주 표에서 '계약완료' 인 것을 직접 읽어 고르게 한다
        List<HashMap<String, Object>> billRows = new ArrayList<HashMap<String, Object>>();
        List<HashMap<String, Object>> readyOrders = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            billRows = queryList(conn, "SELECT B.BILL_ID, B.ORDER_ID, B.CUST_ID, C.CUST_NM, B.BILL_DT, B.TOTAL_AMT, B.ETAX_NO, B.ISSUE_STATUS "
                    + "FROM TB_BILL B LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = B.CUST_ID ORDER BY B.BILL_DT DESC, B.BILL_ID DESC LIMIT 100", null);
            readyOrders = queryList(conn, "SELECT O.ORDER_ID, O.CUST_ID, C.CUST_NM, O.CONTRACT_ID, O.ORDER_AMT FROM TB_ORDER O "
                    + "INNER JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID WHERE O.ORDER_STATUS = '계약완료' ORDER BY O.ORDER_DT", null);
        } catch (Exception e) {
            printErr(out, "청구 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>청구</h2>
<form name="frmBill" onsubmit="return false;" class="searchbox">
    <input type="hidden" name="custId" value=""/><input type="hidden" name="orderId" value=""/><input type="hidden" name="contractId" value=""/>
    수기 발행 수주 <select name="pick" onchange="fnPick(this)"><option value="">선택</option>
<% for (HashMap<String, Object> ro : readyOrders) { %>
        <option value="<%= ro.get("ORDER_ID") %>" data-cust="<%= ro.get("CUST_ID") %>" data-contract="<%= ro.get("CONTRACT_ID") %>" data-amt="<%= ro.get("ORDER_AMT") %>"><%= esc(ro.get("CUST_NM")) %> / <%= ro.get("ORDER_ID") %></option>
<% } %>
    </select> 공급가액 <input type="text" name="supplyAmt" size="12" onkeyup="numOnly(this)"/>
    <button type="button" class="btn btn-main" onclick="fnIssue()">발행</button>
</form>
<table class="list">
    <thead><tr><th>청구번호</th><th>거래처</th><th>청구일</th><th>합계</th><th>승인번호</th><th>상태</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> b : billRows) { String st = (String) b.get("ISSUE_STATUS"); %>
        <tr><td><%= b.get("BILL_ID") %></td><td><%= esc(b.get("CUST_NM")) %></td><td><%= b.get("BILL_DT") %></td><td class="num"><%= fmtAmt(b.get("TOTAL_AMT")) %></td>
            <td><%= esc(b.get("ETAX_NO")) %></td><td><%= "10".equals(st) ? "발행" : "90".equals(st) ? "실패" : "대기" %></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnPick(sel) {
    var op = sel.options[sel.selectedIndex], f = document.frmBill;
    f.orderId.value = sel.value;
    f.custId.value = op.getAttribute('data-cust') || '';
    f.contractId.value = op.getAttribute('data-contract') || '';
    f.supplyAmt.value = op.getAttribute('data-amt') || '';
}
function fnIssue() {
    var f = document.frmBill;
    if (f.orderId.value == '') { alert('수주를 선택하세요.'); return; }
    callCmd('billIssue', { custId: f.custId.value, orderId: f.orderId.value, contractId: f.contractId.value, supplyAmt: f.supplyAmt.value }, function(res) {
        alert('발행했습니다. 승인번호 ' + res.etaxNo);
        goCmd('billList');
    });
}
</script>
<%
    } else if ("collectList".equals(cmd)) {
        // 수금 목록 + 등록 : 거래처를 고르면 그 거래처의 미수 청구를 청구 쪽 cmd 로 읽어 온다
        List<HashMap<String, Object>> collectRows = new ArrayList<HashMap<String, Object>>();
        List<HashMap<String, Object>> collectCusts = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        try {
            conn = getConn();
            collectRows = queryList(conn, "SELECT L.COLLECT_ID, L.BILL_ID, L.CUST_ID, C.CUST_NM, L.COLLECT_DT, L.COLLECT_AMT, L.COLLECT_METHOD "
                    + "FROM TB_COLLECT L LEFT OUTER JOIN TB_CUSTOMER C ON C.CUST_ID = L.CUST_ID ORDER BY L.COLLECT_DT DESC, L.COLLECT_ID DESC LIMIT 100", null);
            collectCusts = queryList(conn, "SELECT CUST_ID, CUST_NM FROM TB_CUSTOMER WHERE USE_YN = 'Y' ORDER BY CUST_NM", null);
        } catch (Exception e) {
            printErr(out, "수금 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>수금</h2>
<form name="frmCollect" onsubmit="return false;" class="searchbox">
    <input type="hidden" name="orderId" value=""/><input type="hidden" name="custId" value=""/>
    거래처 <select id="selCust" onchange="fnCustChange(this.value)"><option value="">선택</option>
<% for (HashMap<String, Object> cc : collectCusts) { %><option value="<%= cc.get("CUST_ID") %>"><%= esc(cc.get("CUST_NM")) %></option><% } %>
    </select>
    청구 <select name="billId" onchange="fnBillChange(this)"><option value="">선택</option></select>
    수금액 <input type="text" name="collectAmt" size="12" onkeyup="numOnly(this)"/> 방법 <%= codeSelect("collectMethod", "COLLECT_METHOD", "01", null) %>
    <button type="button" class="btn btn-main" onclick="fnCollect()">수금 등록</button>
</form>
<table class="list">
    <thead><tr><th>수금번호</th><th>거래처</th><th>청구번호</th><th>수금일</th><th>금액</th><th>방법</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> l : collectRows) { %>
        <tr><td><%= l.get("COLLECT_ID") %></td><td><%= esc(l.get("CUST_NM")) %></td><td><%= l.get("BILL_ID") %></td><td><%= l.get("COLLECT_DT") %></td>
            <td class="num"><%= fmtAmt(l.get("COLLECT_AMT")) %></td><td><%= codeName("COLLECT_METHOD", (String) l.get("COLLECT_METHOD")) %></td></tr>
<% } %>
    </tbody>
</table>
<script type="text/javascript">
function fnCustChange(custId) {
    var f = document.frmCollect;
    f.custId.value = custId;
    f.billId.length = 1;
    if (custId == '') return;
    callCmd('billOpenList', { custId: custId }, function(res) {
        for (var i = 0; i < res.list.length; i++) {
            var op = new Option(res.list[i].billId + ' (남은 금액 ' + fmtNum(res.list[i].balance) + ')', res.list[i].billId);
            op.setAttribute('data-order', res.list[i].orderId);
            op.setAttribute('data-balance', res.list[i].balance);
            f.billId.options[f.billId.length] = op;
        }
    });
}
function fnBillChange(sel) {
    var op = sel.options[sel.selectedIndex];
    document.frmCollect.orderId.value = op.getAttribute('data-order') || '';
    document.frmCollect.collectAmt.value = op.getAttribute('data-balance') || '';
}
function fnCollect() {
    var f = document.frmCollect;
    if (f.billId.value == '' || f.collectAmt.value == '') { alert('청구와 수금액을 확인하세요.'); return; }
    callCmd('collectSave', formToParams(f), function(res) { alert(res.balance <= 0 ? '완납 처리되었습니다.' : '남은 금액 ' + fmtNum(res.balance) + '원'); goCmd('collectList'); });
}
</script>
<%
    } else if ("arrearsList".equals(cmd)) {
        // 미수 현황 : 발행된 청구 중 아직 다 못 받은 건 (2017.03 화면이라 직접 JDBC.  SQL 은 arrearsData · runArrearsNotice 와 같은 모양)
        int iOverdue = toInt(request.getParameter("overdueDays"), 0);
        List<HashMap<String, Object>> arrearsRows = new ArrayList<HashMap<String, Object>>();
        Connection conn = null;
        Statement st = null;
        ResultSet rs = null;
        try {
            conn = getConn();
            st = conn.createStatement();
            rs = st.executeQuery("SELECT B.BILL_ID, B.CUST_ID, C.CUST_NM, B.BILL_DT, B.TOTAL_AMT, IFNULL(P.PAID_AMT, 0) AS PAID_AMT, "
                    + "B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) AS ARREARS_AMT, DATEDIFF(NOW(), B.BILL_DT) AS OVERDUE_DAYS "
                    + "FROM TB_BILL B INNER JOIN TB_CUSTOMER C ON C.CUST_ID = B.CUST_ID "
                    + "LEFT OUTER JOIN (SELECT BILL_ID, SUM(COLLECT_AMT) AS PAID_AMT FROM TB_COLLECT GROUP BY BILL_ID) P ON P.BILL_ID = B.BILL_ID "
                    + "WHERE B.ISSUE_STATUS = '10' AND B.TOTAL_AMT - IFNULL(P.PAID_AMT, 0) > 0 AND DATEDIFF(NOW(), B.BILL_DT) >= " + iOverdue
                    + " ORDER BY OVERDUE_DAYS DESC, B.BILL_ID");
            while (rs.next()) {
                HashMap<String, Object> row = new HashMap<String, Object>();
                for (String k : new String[] { "BILL_ID", "CUST_NM", "BILL_DT", "TOTAL_AMT", "PAID_AMT", "ARREARS_AMT", "OVERDUE_DAYS" }) {
                    row.put(k, rs.getObject(k));
                }
                arrearsRows.add(row);
            }
        } catch (Exception e) {
            printErr(out, "미수 조회", e);
        } finally {
            closeAll(rs, st, conn);
        }
%>
<h2>미수 현황</h2>
<form method="get" action="<%= thisPage %>" class="searchbox">
    <input type="hidden" name="cmd" value="arrearsList"/>
    경과일 <input type="text" name="overdueDays" size="4" value="<%= iOverdue %>"/>일 이상 <button type="submit" class="btn btn-main">조회</button>
<% if ("ADMIN".equals(authCd)) { %>
    <a href="<%= thisPage %>?cmd=batchArrears&key=<%= BATCH_KEY %>" onclick="return confirm('30일 넘은 미수 거래처에 안내 메일을 지금 보냅니다.');">[미수 안내 메일 지금 발송]</a>
<% } %>
</form>
<table class="list">
    <thead><tr><th>청구번호</th><th>거래처</th><th>청구일</th><th>청구금액</th><th>수금액</th><th>미수금</th><th>경과일</th></tr></thead>
    <tbody>
<% for (HashMap<String, Object> a : arrearsRows) { %>
        <tr><td><%= a.get("BILL_ID") %></td><td><%= esc(a.get("CUST_NM")) %></td><td><%= a.get("BILL_DT") %></td><td class="num"><%= fmtAmt(a.get("TOTAL_AMT")) %></td>
            <td class="num"><%= fmtAmt(a.get("PAID_AMT")) %></td><td class="num warn"><%= fmtAmt(a.get("ARREARS_AMT")) %></td><td><%= a.get("OVERDUE_DAYS") %></td></tr>
<% } %>
    </tbody>
</table>
<%
    } else if ("salesReport".equals(cmd)) {
        // 매출 리포트 : 거래처 · 수주 · 수주품목 · 제품 · 사원 · 청구 · 수금을 한 번에 조인해서 읽고 거래처별로 합산한다 (2021.03 김철수)
        List<Object> rptParams = new ArrayList<Object>();
        String strRptWhere = salesWhereSql(request, rptParams, authCd, loginId);
        List<HashMap<String, Object>> rptRows = new ArrayList<HashMap<String, Object>>();
        LinkedHashMap<String, long[]> custSum = new LinkedHashMap<String, long[]>();
        Connection conn = null;
        try {
            conn = getConn();
            rptRows = queryList(conn, "SELECT C.CUST_ID, C.CUST_NM, C.CUST_GRADE, U.USER_NM AS CHARGE_USER_NM, O.ORDER_ID, O.ORDER_DT, O.ORDER_STATUS, "
                    + "P.PRODUCT_NM, OI.QTY, OI.AMT AS ITEM_AMT, B.TOTAL_AMT AS BILL_AMT, IFNULL(CL.COLLECT_AMT, 0) AS COLLECT_AMT"
                    + salesFromSql() + strRptWhere + " ORDER BY O.ORDER_DT DESC, C.CUST_NM, P.PRODUCT_NM LIMIT 500", rptParams.toArray());
            for (HashMap<String, Object> r : rptRows) {
                long[] sum = custSum.get((String) r.get("CUST_NM"));
                if (sum == null) { sum = new long[3]; custSum.put((String) r.get("CUST_NM"), sum); }
                sum[0] += ((Number) r.get("ITEM_AMT")).longValue();
                sum[1] += r.get("BILL_AMT") == null ? 0L : ((Number) r.get("BILL_AMT")).longValue();
                sum[2] += ((Number) r.get("COLLECT_AMT")).longValue();
            }
        } catch (Exception e) {
            printErr(out, "리포트 조회", e);
        } finally {
            closeAll(null, null, conn);
        }
%>
<h2>매출 리포트</h2>
<form method="get" action="<%= thisPage %>" class="searchbox">
    <input type="hidden" name="cmd" value="salesReport"/>
    기간 <input type="text" name="fromDt" size="10" value="<%= esc(request.getParameter("fromDt")) %>"/> ~ <input type="text" name="toDt" size="10" value="<%= esc(request.getParameter("toDt")) %>"/>
    <button type="submit" class="btn btn-main">조회</button>
    <a href="<%= thisPage %>?cmd=salesExcel&fromDt=<%= esc(request.getParameter("fromDt")) %>&toDt=<%= esc(request.getParameter("toDt")) %>">엑셀</a>
</form>
<h3>거래처별 합계</h3>
<table class="list" style="width:60%">
    <thead><tr><th>거래처</th><th>수주 품목 금액</th><th>청구 금액</th><th>수금 금액</th></tr></thead>
    <tbody>
<% for (Map.Entry<String, long[]> en : custSum.entrySet()) { %>
        <tr><td><%= esc(en.getKey()) %></td><td class="num"><%= fmtAmt(en.getValue()[0]) %></td><td class="num"><%= fmtAmt(en.getValue()[1]) %></td><td class="num"><%= fmtAmt(en.getValue()[2]) %></td></tr>
<% } %>
    </tbody>
</table>
<%
    } else if ("custHist".equals(cmd)) {
        // 거래처 변경 이력 (2018.01 추가).  2018.11 에 메뉴에서 뺐다
        Connection conn = getConn();
        for (HashMap<String, Object> h : getCustHistory(conn, request.getParameter("custId"))) {
            out.println(h.get("CHG_DT") + " " + h.get("CHG_COL") + " : " + h.get("OLD_VAL") + " -> " + h.get("NEW_VAL") + "<br/>");
        }
        closeAll(null, null, conn);
    } else {
%>
<p class="err">알 수 없는 명령입니다 : <%= esc(cmd) %></p>
<%
    }   // ---- [화면 cmd] 끝
%>
</div>
</body>
</html>
