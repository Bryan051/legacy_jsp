<%--
================================================================================
  order_main.jsp  -  OMS 수주관리 (거래처 · 수주 · 청구/수금)        Tomcat 8 / JDK 1.8 / MySQL 5.7

  화면과 처리가 이 파일 하나에 있다.  주소는 order_main.jsp?cmd=<명령> (없으면 main).
  처리 cmd 는 위쪽 분기(JSON 으로 답함), 화면 cmd 는 아래쪽 분기.

  변경 이력
  2017.04  홍길동  최초 작성 (거래처 · 수주)
  2017.10  김철수  청구 · 수금
  2019.03  홍길동  수주 이력 화면 막음, TB_ORDER_HIST 삭제
  2019.08  홍길동  여신 관리 (한도 · 여신상태), 공통코드 application 캐시
  2020.02  김철수  수주 완료 때 전자세금계산서 바로 발행 (고객 요청)
  2021.03  김철수  대시보드
  2022.05  홍길동  연체 처리 배치
  2023.01  김철수  그룹웨어 SSO 적용 (로그인 화면 · 사용자 표 없앰)

  설치 메모
  1) 아래 DDL 을 oms 스키마에 실행한다.
  2) Tomcat context.xml 에 jdbc/omsDS 등록 (없으면 선언부 DB_URL 로 직접 연결).
  3) 로그인은 그룹웨어 SSO 가 하고, 세션 LOGIN_USER 에 사번 · 이름 · 권한을 넣어 준다 (sso_login.jsp 는 SSO 업체 파일).
  4) cron :  0 6 * * *  wget -q -O - "http://localhost:8080/oms/order_main.jsp?cmd=batchArrears&key=배치키"
  5) TB_CODE 에 CREDIT_STATUS · ORDER_STATUS · COLLECT_METHOD 를 먼저 넣고, 고친 뒤에는 [코드 캐시 갱신].
================================================================================

SET NAMES utf8;

CREATE TABLE IF NOT EXISTS TB_CODE (
    GRP_CD VARCHAR(20) NOT NULL,
    CD VARCHAR(20) NOT NULL,
    CD_NM VARCHAR(100) NOT NULL,
    SORT_ORD INT NOT NULL DEFAULT 0,
    PRIMARY KEY (GRP_CD, CD)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='공통코드';

CREATE TABLE IF NOT EXISTS TB_CUSTOMER (
    CUST_ID VARCHAR(20) NOT NULL,
    CUST_NM VARCHAR(100) NOT NULL,
    BIZ_NO VARCHAR(12) NULL COMMENT '사업자등록번호',
    EMAIL VARCHAR(100) NULL COMMENT '세금계산서 받는 메일',
    SALES_ID VARCHAR(20) NULL COMMENT '담당 영업 (SSO 사번)',
    CREDIT_LIMIT DECIMAL(15,0) NOT NULL DEFAULT 0 COMMENT '여신한도',
    CREDIT_STATUS VARCHAR(2) NOT NULL DEFAULT '01' COMMENT '01정상 02미수 03연체',
    USE_YN CHAR(1) NOT NULL DEFAULT 'Y',
    REG_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (CUST_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='거래처';

CREATE TABLE IF NOT EXISTS TB_ORDER (
    ORDER_ID VARCHAR(20) NOT NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    CUST_NM VARCHAR(100) NULL COMMENT '거래처명 (목록용)',
    ORDER_DT DATE NOT NULL,
    ORDER_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    ORDER_STATUS VARCHAR(2) NOT NULL DEFAULT '10' COMMENT '10접수 20청구완료 30수금완료 90취소',
    REG_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    UPD_DT DATETIME NULL,
    PRIMARY KEY (ORDER_ID),
    CONSTRAINT FK_ORDER_CUST FOREIGN KEY (CUST_ID) REFERENCES TB_CUSTOMER (CUST_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수주';

CREATE TABLE IF NOT EXISTS TB_ORDER_ITEM (
    ORDER_ID VARCHAR(20) NOT NULL,
    ITEM_SEQ INT NOT NULL,
    ITEM_NM VARCHAR(100) NOT NULL,
    QTY INT NOT NULL DEFAULT 1,
    UNIT_PRICE DECIMAL(15,0) NOT NULL DEFAULT 0,
    AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    PRIMARY KEY (ORDER_ID, ITEM_SEQ),
    CONSTRAINT FK_OITEM_ORDER FOREIGN KEY (ORDER_ID) REFERENCES TB_ORDER (ORDER_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수주 품목';

CREATE TABLE IF NOT EXISTS TB_BILL (
    BILL_ID VARCHAR(20) NOT NULL,
    ORDER_ID VARCHAR(20) NOT NULL,
    CUST_ID VARCHAR(20) NOT NULL,
    CUST_NM VARCHAR(100) NOT NULL COMMENT '발행 당시 거래처명',
    BIZ_NO VARCHAR(12) NULL COMMENT '발행 당시 사업자번호',
    BILL_DT DATE NOT NULL,
    SUPPLY_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    TAX_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    TOTAL_AMT DECIMAL(15,0) NOT NULL DEFAULT 0,
    ETAX_NO VARCHAR(30) NULL COMMENT '전자세금계산서 승인번호',
    ISSUE_STATUS VARCHAR(2) NOT NULL DEFAULT '00' COMMENT '00대기 10발행 90실패',
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (BILL_ID),
    CONSTRAINT FK_BILL_ORDER FOREIGN KEY (ORDER_ID) REFERENCES TB_ORDER (ORDER_ID)
    -- CUST_ID FK 없음
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='청구(세금계산서)';

CREATE TABLE IF NOT EXISTS TB_COLLECT (
    COLLECT_ID INT NOT NULL AUTO_INCREMENT,
    BILL_ID VARCHAR(20) NOT NULL,
    COLLECT_DT DATE NOT NULL,
    COLLECT_AMT DECIMAL(15,0) NOT NULL,
    COLLECT_METHOD VARCHAR(2) NULL COMMENT '01계좌이체 02현금 03어음',
    REG_ID VARCHAR(20) NULL,
    REG_DT DATETIME NOT NULL,
    PRIMARY KEY (COLLECT_ID),
    CONSTRAINT FK_COLLECT_BILL FOREIGN KEY (BILL_ID) REFERENCES TB_BILL (BILL_ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COMMENT='수금';
--%>
<%@ page language="java" contentType="text/html; charset=UTF-8" pageEncoding="UTF-8" %>
<%@ page import="java.sql.*, java.util.*, java.text.*, java.io.*, java.net.*, javax.naming.*, javax.sql.*" %>
<%!
    // ---- 상수 (운영 반영 전에 DB_PASS · BATCH_KEY 확인할 것)
    private static final String JNDI_NAME  = "java:comp/env/jdbc/omsDS";
    private static final String DB_URL     = "jdbc:mysql://127.0.0.1:3306/oms?useUnicode=true&characterEncoding=utf8";
    private static final String DB_USER    = "omsuser";
    private static final String DB_PASS    = "changeme";
    private static final String ETAX_URL   = "http://etax.example.com/api/issue";   // 연동 업체 주소
    private static final String BATCH_KEY  = "changeme";                            // cron 이 넘기는 키
    private static final String CODE_CACHE = "OMS_CODE_CACHE";                      // application 속성 이름
    private static final double VAT_RATE   = 0.1;
    private static int idSeq = 0;

    private Connection getConn() throws Exception {
        try {
            return ((DataSource) new InitialContext().lookup(JNDI_NAME)).getConnection();
        } catch (NamingException ne) {   // 개발 PC
            Class.forName("com.mysql.jdbc.Driver");
            return DriverManager.getConnection(DB_URL, DB_USER, DB_PASS);
        }
    }

    private void closeAll(ResultSet rs, Statement st, Connection conn) {
        try { if (rs != null) rs.close(); } catch (Exception e) { }
        try { if (st != null) st.close(); } catch (Exception e) { }
        try { if (conn != null) conn.close(); } catch (Exception e) { }
    }

    private void rollback(Connection conn) {
        try { if (conn != null) conn.rollback(); } catch (Exception e) { }
    }

    // ---- DB 도우미 : 조회 결과는 열 이름(대문자)을 키로 한 Map
    private List<Map<String, Object>> list(Connection conn, String sql, Object... p) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(sql);
        for (int i = 0; i < p.length; i++) ps.setObject(i + 1, p[i]);
        ResultSet rs = ps.executeQuery();
        List<Map<String, Object>> rows = new ArrayList<Map<String, Object>>();
        while (rs.next()) {
            Map<String, Object> row = new HashMap<String, Object>();
            for (int c = 1; c <= rs.getMetaData().getColumnCount(); c++) row.put(rs.getMetaData().getColumnLabel(c).toUpperCase(), rs.getObject(c));
            rows.add(row);
        }
        closeAll(rs, ps, null);
        return rows;
    }

    private Map<String, Object> one(Connection conn, String sql, Object... p) throws SQLException {
        List<Map<String, Object>> rows = list(conn, sql, p);
        return rows.isEmpty() ? null : rows.get(0);
    }

    private int exec(Connection conn, String sql, Object... p) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(sql);
        for (int i = 0; i < p.length; i++) ps.setObject(i + 1, p[i]);
        int n = ps.executeUpdate();
        ps.close();
        return n;
    }

    // ---- 글자 · 금액 · JSON
    private String nvl(Object s, String d) { return s == null || s.toString().length() == 0 ? d : s.toString(); }

    private long toLong(Object s) {
        try { return new java.math.BigDecimal(s.toString().replace(",", "").trim()).longValue(); } catch (Exception e) { return 0; }
    }

    private String fmt(Object n) { return new DecimalFormat("#,##0").format(toLong(n)); }

    private String esc(Object s) {
        return nvl(s, "").replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&#39;");
    }

    private String json(Object v) {
        if (v == null || v instanceof Number || v instanceof Boolean) return String.valueOf(v);
        return "\"" + v.toString().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\r", "") + "\"";
    }

    /** printJson(response, out, "ok", true, "키", 값, ...) */
    private void printJson(HttpServletResponse res, JspWriter out, Object... kv) throws IOException {
        StringBuilder sb = new StringBuilder("{");
        for (int i = 0; i + 1 < kv.length; i += 2) sb.append(i > 0 ? "," : "").append(json(kv[i])).append(':').append(json(kv[i + 1]));
        out.clearBuffer();
        res.setContentType("application/json; charset=UTF-8");
        out.print(sb.append('}'));
    }

    /** 채번 : 접두 + 년월일시분초 + 일련 2자리 */
    private synchronized String genId(String prefix) {
        idSeq = (idSeq + 1) % 100;
        return prefix + new SimpleDateFormat("yyMMddHHmmss").format(new java.util.Date()) + String.format("%02d", idSeq);
    }

    // ---- 공통코드 : application 에 그룹별로 올려 두고 모든 화면이 같이 쓴다 (2019.08 홍길동, 10분마다 다시 읽음)
    @SuppressWarnings("unchecked")
    private Map<String, Map<String, String>> loadCodes(ServletContext app, Connection conn, boolean force) throws SQLException {
        Map<String, Map<String, String>> codes = (Map<String, Map<String, String>>) app.getAttribute(CODE_CACHE);
        Long at = (Long) app.getAttribute(CODE_CACHE + "_AT");
        if (!force && codes != null && at != null && System.currentTimeMillis() - at < 600000L) return codes;
        codes = new HashMap<String, Map<String, String>>();
        for (Map<String, Object> r : list(conn, "SELECT GRP_CD, CD, CD_NM FROM TB_CODE ORDER BY GRP_CD, SORT_ORD")) {
            if (codes.get(r.get("GRP_CD")) == null) codes.put((String) r.get("GRP_CD"), new LinkedHashMap<String, String>());
            codes.get(r.get("GRP_CD")).put((String) r.get("CD"), (String) r.get("CD_NM"));
        }
        app.setAttribute(CODE_CACHE, codes);
        app.setAttribute(CODE_CACHE + "_AT", System.currentTimeMillis());
        return codes;
    }

    private String codeNm(Map<String, Map<String, String>> codes, String grp, Object cd) {
        String nm = codes.containsKey(grp) ? codes.get(grp).get(String.valueOf(cd)) : null;
        return nm == null ? nvl(cd, "") : nm;
    }

    private String codeOpts(Map<String, Map<String, String>> codes, String grp) {
        StringBuilder sb = new StringBuilder();
        for (Map.Entry<String, String> e : codes.get(grp).entrySet()) sb.append("<option value=\"" + e.getKey() + "\">" + esc(e.getValue()) + "</option>");
        return sb.toString();
    }

    // ---- 여러 화면이 같이 부르는 업무 메서드
    /** 여신상태 바꾸기 (01 정상 / 02 미수 / 03 연체) */
    private void updateCreditStatus(Connection conn, String custId, String status) throws SQLException {
        exec(conn, "UPDATE TB_CUSTOMER SET CREDIT_STATUS = ?, UPD_DT = NOW() WHERE CUST_ID = ?", status, custId);
    }

    /** 미수 금액 = 발행된 청구 합계 - 받은 금액 */
    private long arrearsAmt(Connection conn, String custId) throws SQLException {
        return toLong(one(conn, "SELECT IFNULL(SUM(B.TOTAL_AMT - IFNULL((SELECT SUM(C.COLLECT_AMT) FROM TB_COLLECT C WHERE C.BILL_ID = B.BILL_ID), 0)), 0) AS AMT "
                              + "FROM TB_BILL B WHERE B.CUST_ID = ? AND B.ISSUE_STATUS = '10'", custId).get("AMT"));
    }

    /** 수주 전 여신 확인 : 안 되면 문구, 되면 null */
    private String checkCredit(Connection conn, String custId, long addAmt) throws SQLException {
        Map<String, Object> c = one(conn, "SELECT CREDIT_LIMIT, CREDIT_STATUS FROM TB_CUSTOMER WHERE CUST_ID = ? AND USE_YN = 'Y'", custId);
        if (c == null) return "없는 거래처입니다.";
        if ("03".equals(c.get("CREDIT_STATUS"))) return "연체 거래처라 수주할 수 없습니다.";
        if (toLong(c.get("CREDIT_LIMIT")) < arrearsAmt(conn, custId) + addAmt) return "여신한도 초과입니다.";
        return null;
    }

    // ---- 외부 연동 : 전자세금계산서 발행 (2020.02 김철수)
    private String callEtax(String billId, String bizNo, String custNm, String email, long supply, long tax) throws Exception {
        HttpURLConnection hc = (HttpURLConnection) new URL(ETAX_URL).openConnection();
        hc.setConnectTimeout(3000);
        hc.setReadTimeout(5000);
        hc.setRequestMethod("POST");
        hc.setDoOutput(true);
        hc.setRequestProperty("Content-Type", "application/json; charset=UTF-8");
        OutputStream os = hc.getOutputStream();
        os.write(("{\"billId\":\"" + billId + "\",\"bizNo\":\"" + bizNo + "\",\"custNm\":\"" + custNm + "\",\"email\":\"" + email
                + "\",\"supplyAmt\":" + supply + ",\"taxAmt\":" + tax + "}").getBytes("UTF-8"));
        os.close();
        if (hc.getResponseCode() != 200) throw new IOException("etax 응답 " + hc.getResponseCode());
        Scanner sc = new Scanner(hc.getInputStream(), "UTF-8").useDelimiter("\\A");
        String res = sc.hasNext() ? sc.next() : "";
        sc.close();
        int p = res.indexOf("\"etaxNo\":\"");
        if (p < 0) throw new IOException("승인번호 없음 : " + res);
        return res.substring(p + 10, res.indexOf('"', p + 10));
    }

    /** 수주 이력 백업 (2018.06 홍길동) */
    private void backupOrderHist(Connection conn, String orderId) throws SQLException {
        exec(conn, "INSERT INTO TB_ORDER_HIST SELECT * FROM TB_ORDER WHERE ORDER_ID = ?", orderId);
    }
%>
<%
    // ========
    //  공통 처리 : 인코딩 · cmd · 로그인 검사
    // ========
    request.setCharacterEncoding("UTF-8");
    String cmd = nvl(request.getParameter("cmd"), "main");
    String thisPage = request.getContextPath() + "/order_main.jsp";

    // 로그인 사용자 : SSO 가 세션에 HashMap 으로 넣어 준다 (USER_ID, USER_NM, AUTH_CD)
    HashMap loginUser = (HashMap) session.getAttribute("LOGIN_USER");
    String loginId = loginUser == null ? "" : (String) loginUser.get("USER_ID");
    String loginNm = loginUser == null ? "" : (String) loginUser.get("USER_NM");
    String authCd  = loginUser == null ? "" : (String) loginUser.get("AUTH_CD");
    boolean bAdmin = "ADMIN".equals(authCd);

    if (loginUser == null && !cmd.startsWith("batch")) {      // 배치는 key 로 확인
        if ("XMLHttpRequest".equals(request.getHeader("X-Requested-With"))) {
            response.setStatus(401);
            printJson(response, out, "ok", false, "msg", "로그인이 필요합니다.");
        } else {
            response.sendRedirect(request.getContextPath() + "/sso_login.jsp?returnUrl=" + URLEncoder.encode(thisPage, "UTF-8"));
        }
        return;
    }
    if ("cacheReload".equals(cmd) && !bAdmin) {
        printJson(response, out, "ok", false, "msg", "권한이 없습니다.");
        return;
    }

    // ========
    //  [처리 전용 cmd]  JSON 으로 답한다
    // ========
    if (",custSave,custDelete,custCreditInfo,orderSave,orderComplete,collectSave,batchArrears,cacheReload,".contains("," + cmd + ",")) {
        Connection conn = null;
        try {
            conn = getConn();
            if ("custSave".equals(cmd)) {
                // ---- 거래처 저장 (새로 · 수정)
                String custId = nvl(request.getParameter("custId"), genId("C"));
                String custNm = nvl(request.getParameter("custNm"), "").trim();
                conn.setAutoCommit(false);
                exec(conn, "INSERT INTO TB_CUSTOMER (CUST_ID, CUST_NM, BIZ_NO, EMAIL, SALES_ID, CREDIT_LIMIT, REG_ID, REG_DT) VALUES (?, ?, ?, ?, ?, ?, ?, NOW()) "
                         + "ON DUPLICATE KEY UPDATE CUST_NM = VALUES(CUST_NM), BIZ_NO = VALUES(BIZ_NO), EMAIL = VALUES(EMAIL), "
                         + "SALES_ID = VALUES(SALES_ID), CREDIT_LIMIT = VALUES(CREDIT_LIMIT), UPD_DT = NOW()",
                     custId, custNm, request.getParameter("bizNo"), request.getParameter("email"),
                     nvl(request.getParameter("salesId"), loginId), toLong(request.getParameter("creditLimit")), loginId);
                exec(conn, "UPDATE TB_ORDER SET CUST_NM = ? WHERE CUST_ID = ?", custNm, custId);   // 수주 목록 거래처명도 같이 (2019.08 홍길동)
                conn.commit();
                printJson(response, out, "ok", true, "custId", custId);

            } else if ("custDelete".equals(cmd)) {
                // ---- 거래처 사용중지 (지우지 않는다)
                String custId = request.getParameter("custId");
                if (arrearsAmt(conn, custId) > 0) {
                    printJson(response, out, "ok", false, "msg", "미수가 남아 있어 사용중지할 수 없습니다.");
                } else {
                    conn.setAutoCommit(false);
                    exec(conn, "UPDATE TB_CUSTOMER SET USE_YN = 'N', UPD_DT = NOW() WHERE CUST_ID = ?", custId);
                    exec(conn, "UPDATE TB_ORDER SET ORDER_STATUS = '90', UPD_DT = NOW() WHERE CUST_ID = ? AND ORDER_STATUS = '10'", custId);
                    conn.commit();
                    printJson(response, out, "ok", true);
                }

            } else if ("custCreditInfo".equals(cmd)) {
                // ---- 여신 정보 (수주 · 청구 화면에서 부른다)
                String custId = request.getParameter("custId");
                Map<String, Object> c = one(conn, "SELECT CUST_NM, CREDIT_LIMIT, CREDIT_STATUS FROM TB_CUSTOMER WHERE CUST_ID = ?", custId);
                long arrears = arrearsAmt(conn, custId);
                printJson(response, out, "ok", true, "custId", custId, "custNm", c.get("CUST_NM"),
                    "creditLimit", c.get("CREDIT_LIMIT"), "creditStatus", c.get("CREDIT_STATUS"),
                    "creditStatusNm", codeNm(loadCodes(application, conn, false), "CREDIT_STATUS", c.get("CREDIT_STATUS")),
                    "arrears", arrears, "available", toLong(c.get("CREDIT_LIMIT")) - arrears);

            } else if ("orderSave".equals(cmd)) {
                // ---- 수주 등록
                String custId = request.getParameter("custId");
                String[] itemNm = request.getParameterValues("itemNm"), qty = request.getParameterValues("qty"), price = request.getParameterValues("unitPrice");
                long amt = 0;
                for (int i = 0; i < itemNm.length; i++) amt += toLong(qty[i]) * toLong(price[i]);
                String err = checkCredit(conn, custId, Math.round(amt * (1 + VAT_RATE)));
                if (err != null) {
                    printJson(response, out, "ok", false, "msg", err);
                } else {
                    conn.setAutoCommit(false);
                    String orderId = genId("O");
                    Map<String, Object> c = one(conn, "SELECT CUST_NM FROM TB_CUSTOMER WHERE CUST_ID = ?", custId);
                    exec(conn, "INSERT INTO TB_ORDER (ORDER_ID, CUST_ID, CUST_NM, ORDER_DT, ORDER_AMT, ORDER_STATUS, REG_ID, REG_DT) "
                             + "VALUES (?, ?, ?, CURDATE(), ?, '10', ?, NOW())", orderId, custId, c.get("CUST_NM"), amt, loginId);
                    for (int i = 0, seq = 0; i < itemNm.length; i++) {
                        if (itemNm[i].trim().length() == 0) continue;
                        exec(conn, "INSERT INTO TB_ORDER_ITEM (ORDER_ID, ITEM_SEQ, ITEM_NM, QTY, UNIT_PRICE, AMT) VALUES (?, ?, ?, ?, ?, ?)",
                             orderId, ++seq, itemNm[i].trim(), toLong(qty[i]), toLong(price[i]), toLong(qty[i]) * toLong(price[i]));
                    }
                    conn.commit();
                    printJson(response, out, "ok", true, "orderId", orderId);
                }

            } else if ("orderComplete".equals(cmd)) {
                // ---- 수주 완료 = 청구 + 전자세금계산서 발행 (2020.02 김철수, 고객 요청)
                String orderId = request.getParameter("orderId");
                conn.setAutoCommit(false);
                Map<String, Object> o = one(conn, "SELECT O.CUST_ID, O.ORDER_AMT, O.ORDER_STATUS, C.CUST_NM, C.BIZ_NO, C.EMAIL "
                    + "FROM TB_ORDER O JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID WHERE O.ORDER_ID = ? FOR UPDATE", orderId);
                if (o == null || !"10".equals(o.get("ORDER_STATUS"))) throw new Exception("접수 상태 수주만 완료할 수 있습니다.");
                exec(conn, "UPDATE TB_ORDER SET ORDER_STATUS = '20', UPD_DT = NOW() WHERE ORDER_ID = ?", orderId);
                String billId = "B" + orderId.substring(1);           // 수주 하나에 청구 하나
                long supply = toLong(o.get("ORDER_AMT")), tax = Math.round(supply * VAT_RATE);
                exec(conn, "INSERT INTO TB_BILL (BILL_ID, ORDER_ID, CUST_ID, CUST_NM, BIZ_NO, BILL_DT, SUPPLY_AMT, TAX_AMT, TOTAL_AMT, ISSUE_STATUS, REG_DT) "
                         + "VALUES (?, ?, ?, ?, ?, CURDATE(), ?, ?, ?, '00', NOW())",
                     billId, orderId, o.get("CUST_ID"), o.get("CUST_NM"), o.get("BIZ_NO"), supply, tax, supply + tax);
                // 2020.11 발행은 됐는데 아래에서 롤백된 적 있음 - 승인번호는 업체 사이트에서 찾아 손으로 넣었다
                String etaxNo = callEtax(billId, (String) o.get("BIZ_NO"), (String) o.get("CUST_NM"), (String) o.get("EMAIL"), supply, tax);
                exec(conn, "UPDATE TB_BILL SET ETAX_NO = ?, ISSUE_STATUS = '10' WHERE BILL_ID = ?", etaxNo, billId);
                updateCreditStatus(conn, (String) o.get("CUST_ID"), "02");
                conn.commit();
                printJson(response, out, "ok", true, "billId", billId, "etaxNo", etaxNo);

            } else if ("collectSave".equals(cmd)) {
                // ---- 수금 등록 (청구 화면)
                String billId = request.getParameter("billId"), custId = request.getParameter("custId");
                conn.setAutoCommit(false);
                exec(conn, "INSERT INTO TB_COLLECT (BILL_ID, COLLECT_DT, COLLECT_AMT, COLLECT_METHOD, REG_ID, REG_DT) VALUES (?, CURDATE(), ?, ?, ?, NOW())",
                     billId, toLong(request.getParameter("collectAmt")), request.getParameter("collectMethod"), loginId);
                Map<String, Object> b = one(conn, "SELECT B.ORDER_ID, B.TOTAL_AMT - IFNULL(SUM(C.COLLECT_AMT), 0) AS REMAIN "
                    + "FROM TB_BILL B LEFT JOIN TB_COLLECT C ON C.BILL_ID = B.BILL_ID WHERE B.BILL_ID = ? GROUP BY B.ORDER_ID, B.TOTAL_AMT", billId);
                if (toLong(b.get("REMAIN")) <= 0) {
                    exec(conn, "UPDATE TB_ORDER SET ORDER_STATUS = '30', UPD_DT = NOW() WHERE ORDER_ID = ?", b.get("ORDER_ID"));
                }
                updateCreditStatus(conn, custId, arrearsAmt(conn, custId) > 0 ? "02" : "01");
                conn.commit();
                printJson(response, out, "ok", true, "remain", toLong(b.get("REMAIN")));

            } else if ("batchArrears".equals(cmd)) {
                // ---- 연체 처리 배치 (2022.05 홍길동) : 발행 30일 지나도 덜 받았으면 03
                if (!BATCH_KEY.equals(request.getParameter("key"))) {
                    response.sendError(403);
                    return;
                }
                int cnt = 0;
                for (Map<String, Object> r : list(conn, "SELECT DISTINCT B.CUST_ID FROM TB_BILL B WHERE B.ISSUE_STATUS = '10' AND DATEDIFF(CURDATE(), B.BILL_DT) > 30 "
                        + "AND B.TOTAL_AMT > IFNULL((SELECT SUM(C.COLLECT_AMT) FROM TB_COLLECT C WHERE C.BILL_ID = B.BILL_ID), 0)")) {
                    updateCreditStatus(conn, (String) r.get("CUST_ID"), "03");
                    cnt++;
                }
                out.clearBuffer();
                response.setContentType("text/plain; charset=UTF-8");
                out.print("연체 처리 " + cnt + "건");

            } else if ("cacheReload".equals(cmd)) {
                // ---- 공통코드 캐시 다시 읽기 (관리자)
                loadCodes(application, conn, true);
                printJson(response, out, "ok", true);
            }
        } catch (Exception e) {
            rollback(conn);
            printJson(response, out, "ok", false, "msg", "처리 실패 : " + e.getMessage());
        } finally {
            closeAll(null, null, conn);
        }
        return;
    }
%>
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>OMS 수주관리</title>
<style>
body { font: 13px sans-serif; margin: 0; } #menu { background: #2b4a6f; padding: 8px; } #menu a, #menu span { color: #fff; margin-right: 12px; }
#wrap { padding: 12px; } .grid { border-collapse: collapse; } .grid td, .grid th { border: 1px solid #bbb; padding: 3px; } .num { text-align: right; }
</style>
<script>
// 같은 JSP 의 처리 cmd 를 부른다 (응답은 JSON)
function callCmd(cmd, params, cb) {
    var xhr = new XMLHttpRequest(), q = 'cmd=' + cmd;
    for (var k in params) [].concat(params[k]).forEach(function (v) { q += '&' + k + '=' + encodeURIComponent(v); });
    xhr.open('POST', '<%= thisPage %>');
    xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
    xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
    xhr.onload = function () { cb(JSON.parse(xhr.responseText)); };
    xhr.send(q);
}
function fmt(n) { return String(n).replace(/\B(?=(\d{3})+(?!\d))/g, ','); }
</script>
</head>
<body>
<div id="menu">
    <a href="?cmd=main">대시보드</a> <a href="?cmd=custList">거래처</a> <a href="?cmd=orderList">수주</a> <a href="?cmd=billList">청구 · 수금</a>
    <%-- <a href="?cmd=orderHist">수주 이력</a> --%>
<% if (bAdmin) { %>
    <a href="#" onclick="callCmd('cacheReload', {}, function (r) { alert(r.ok ? '갱신했습니다.' : r.msg); }); return false;">[코드 캐시 갱신]</a>
<% } %>
    <span style="float:right"><%= esc(loginNm) %> (<%= esc(authCd) %>)</span>
</div>
<div id="wrap">
<%
    // ========
    //  [화면 cmd]
    // ========
    Connection conn = null;
    try {
        conn = getConn();
        Map<String, Map<String, String>> codes = loadCodes(application, conn, false);

        if ("main".equals(cmd)) {
            // ---- 대시보드
            // 60일 넘은 접수 수주는 취소 (배치 만들기 전 임시, 2021.03 김철수)
            exec(conn, "UPDATE TB_ORDER SET ORDER_STATUS = '90', UPD_DT = NOW() WHERE ORDER_STATUS = '10' AND ORDER_DT < DATE_SUB(CURDATE(), INTERVAL 60 DAY)");
            Map<String, Object> d = one(conn, "SELECT (SELECT COUNT(*) FROM TB_CUSTOMER WHERE USE_YN = 'Y') AS CUST_CNT, "
                + "(SELECT COUNT(*) FROM TB_ORDER WHERE ORDER_STATUS = '10') AS OPEN_CNT, "
                + "(SELECT IFNULL(SUM(ORDER_AMT), 0) FROM TB_ORDER WHERE ORDER_STATUS <> '90' AND DATE_FORMAT(ORDER_DT, '%Y%m') = DATE_FORMAT(CURDATE(), '%Y%m')) AS MONTH_AMT, "
                + "(SELECT IFNULL(SUM(TOTAL_AMT), 0) FROM TB_BILL WHERE ISSUE_STATUS = '10') - (SELECT IFNULL(SUM(COLLECT_AMT), 0) FROM TB_COLLECT) AS ARREARS");
%>
<h3>대시보드</h3>
<table class="grid"><tr><th>거래처</th><th>접수 수주</th><th>이번 달 수주</th><th>미수 합계</th></tr>
<tr><td class="num"><%= d.get("CUST_CNT") %></td><td class="num"><%= d.get("OPEN_CNT") %></td><td class="num"><%= fmt(d.get("MONTH_AMT")) %></td><td class="num"><%= fmt(d.get("ARREARS")) %></td></tr></table>
<%
        } else if ("custList".equals(cmd)) {
            // ---- 거래처 목록 + 등록 · 수정
            String q = nvl(request.getParameter("q"), ""), sort = nvl(request.getParameter("sort"), "C.CUST_NM");
            long pageNo = Math.max(1, toLong(request.getParameter("page")));
            List<Map<String, Object>> rows = list(conn, "SELECT C.CUST_ID, C.CUST_NM, C.BIZ_NO, C.SALES_ID, C.CREDIT_LIMIT, C.CREDIT_STATUS, "
                + "(SELECT IFNULL(SUM(B.TOTAL_AMT), 0) FROM TB_BILL B WHERE B.CUST_ID = C.CUST_ID AND B.ISSUE_STATUS = '10') "
                + "- (SELECT IFNULL(SUM(L.COLLECT_AMT), 0) FROM TB_COLLECT L JOIN TB_BILL B2 ON B2.BILL_ID = L.BILL_ID WHERE B2.CUST_ID = C.CUST_ID) AS ARREARS "
                + "FROM TB_CUSTOMER C WHERE C.USE_YN = 'Y' AND C.CUST_NM LIKE CONCAT('%', ?, '%') AND (? = 'ADMIN' OR C.SALES_ID = ?) "
                + "ORDER BY " + sort + " LIMIT ?, ?", q, authCd, loginId, (pageNo - 1) * 20, 20);
%>
<h3>거래처</h3>
<form><input type="hidden" name="cmd" value="custList">거래처명 <input name="q" value="<%= esc(q) %>"> <button>찾기</button></form>
<table class="grid"><tr><th>ID</th><th><a href="?cmd=custList&sort=C.CUST_NM">거래처명</a></th><th>사업자번호</th><th>담당</th><th>여신한도</th><th>여신상태</th><th><a href="?cmd=custList&sort=ARREARS DESC">미수</a></th><th></th></tr>
<%          for (Map<String, Object> r : rows) { %>
<tr><td><%= r.get("CUST_ID") %></td><td><%= esc(r.get("CUST_NM")) %></td><td><%= esc(r.get("BIZ_NO")) %></td><td><%= esc(r.get("SALES_ID")) %></td>
    <td class="num"><%= fmt(r.get("CREDIT_LIMIT")) %></td><td><%= codeNm(codes, "CREDIT_STATUS", r.get("CREDIT_STATUS")) %></td><td class="num"><%= fmt(r.get("ARREARS")) %></td>
    <td><button onclick="delCust('<%= r.get("CUST_ID") %>')">사용중지</button></td></tr>
<%          } %>
</table>
<h4>거래처 등록 · 수정 (ID 를 비우면 새로)</h4>
<form onsubmit="saveCust(this); return false;">
ID <input name="custId" size="15"> 거래처명 <input name="custNm"> 사업자번호 <input name="bizNo" size="10"> 메일 <input name="email">
담당 사번 <input name="salesId" size="8" value="<%= esc(loginId) %>"> 여신한도 <input name="creditLimit" size="10"> <button>저장</button>
</form>
<script>
function saveCust(f) {
    var p = {};
    ['custId', 'custNm', 'bizNo', 'email', 'salesId', 'creditLimit'].forEach(function (k) { p[k] = f[k].value; });
    callCmd('custSave', p, function (r) { if (r.ok) location.reload(); else alert(r.msg); });
}
function delCust(id) {
    if (confirm('사용중지할까요?')) callCmd('custDelete', { custId: id }, function (r) { if (r.ok) location.reload(); else alert(r.msg); });
}
</script>
<%
        } else if ("orderList".equals(cmd)) {
            // ---- 수주 목록 (담당 거래처 것만, 관리자는 전부)
            List<Map<String, Object>> rows = list(conn, "SELECT O.ORDER_ID, O.CUST_NM, O.ORDER_DT, O.ORDER_AMT, O.ORDER_STATUS FROM TB_ORDER O "
                + "JOIN TB_CUSTOMER C ON C.CUST_ID = O.CUST_ID WHERE (? = 'ADMIN' OR C.SALES_ID = ?) ORDER BY O.ORDER_DT DESC, O.ORDER_ID DESC LIMIT 100", authCd, loginId);
%>
<h3>수주 <a href="?cmd=orderForm">[새 수주]</a></h3>
<table class="grid"><tr><th>수주번호</th><th>거래처</th><th>수주일</th><th>금액</th><th>상태</th><th></th></tr>
<%          for (Map<String, Object> r : rows) { %>
<tr><td><%= r.get("ORDER_ID") %></td><td><%= esc(r.get("CUST_NM")) %></td><td><%= r.get("ORDER_DT") %></td><td class="num"><%= fmt(r.get("ORDER_AMT")) %></td>
    <td><%= codeNm(codes, "ORDER_STATUS", r.get("ORDER_STATUS")) %></td>
    <td><% if ("10".equals(r.get("ORDER_STATUS"))) { %><button onclick="completeOrder('<%= r.get("ORDER_ID") %>')">완료(청구 발행)</button><% } %></td></tr>
<%          } %>
</table>
<script>
function completeOrder(id) {
    if (confirm('수주를 완료하고 세금계산서를 발행합니다.'))
        callCmd('orderComplete', { orderId: id }, function (r) { alert(r.ok ? '발행했습니다. 승인번호 ' + r.etaxNo : r.msg); location.reload(); });
}
</script>
<%
        } else if ("orderForm".equals(cmd)) {
            // ---- 수주 등록 화면
            List<Map<String, Object>> custs = list(conn, "SELECT CUST_ID, CUST_NM FROM TB_CUSTOMER WHERE USE_YN = 'Y' AND (? = 'ADMIN' OR SALES_ID = ?) ORDER BY CUST_NM", authCd, loginId);
%>
<h3>수주 등록</h3>
<form onsubmit="saveOrder(this); return false;">
거래처 <select name="custId" onchange="showCredit(this.value)"><option value="">선택</option>
<%          for (Map<String, Object> c : custs) { %><option value="<%= c.get("CUST_ID") %>"><%= esc(c.get("CUST_NM")) %></option><% } %>
</select> <span id="credit"></span>
<table class="grid"><tr><th>품목</th><th>수량</th><th>단가</th></tr>
<%          for (int i = 0; i < 3; i++) { %><tr><td><input name="itemNm" size="24"></td><td><input name="qty" size="4" value="1"></td><td><input name="unitPrice" size="10"></td></tr><% } %>
</table>
<button>저장</button>
</form>
<script>
// 거래처를 고르면 여신 정보를 보여 준다
function showCredit(custId) {
    var el = document.getElementById('credit');
    if (custId) callCmd('custCreditInfo', { custId: custId }, function (r) {
        el.innerHTML = r.ok ? '여신 ' + r.creditStatusNm + ' · 한도 ' + fmt(r.creditLimit) + ' · 미수 ' + fmt(r.arrears) + ' · 남은 한도 ' + fmt(r.available) : r.msg;
    });
}
function saveOrder(f) {
    var p = { custId: f.custId.value, itemNm: [], qty: [], unitPrice: [] };
    for (var i = 0; i < 3; i++) { p.itemNm.push(f.itemNm[i].value); p.qty.push(f.qty[i].value); p.unitPrice.push(f.unitPrice[i].value); }
    callCmd('orderSave', p, function (r) { if (r.ok) location.href = '?cmd=orderList'; else alert(r.msg); });
}
</script>
<%
        } else if ("billList".equals(cmd)) {
            // ---- 청구 목록 + 수금 등록
            List<Map<String, Object>> rows = list(conn, "SELECT B.BILL_ID, B.CUST_ID, B.CUST_NM, B.BILL_DT, B.TOTAL_AMT, B.ETAX_NO, B.ISSUE_STATUS, O.ORDER_STATUS, "
                + "IFNULL((SELECT SUM(L.COLLECT_AMT) FROM TB_COLLECT L WHERE L.BILL_ID = B.BILL_ID), 0) AS PAID "
                + "FROM TB_BILL B JOIN TB_ORDER O ON O.ORDER_ID = B.ORDER_ID JOIN TB_CUSTOMER C ON C.CUST_ID = B.CUST_ID "
                + "WHERE (? = 'ADMIN' OR C.SALES_ID = ?) ORDER BY B.BILL_DT DESC, B.BILL_ID DESC LIMIT 100", authCd, loginId);
%>
<h3>청구 · 수금</h3>
<script>
// 발행 상태 : 10 발행 / 90 실패 / 그 밖 대기
function issueText(s) { return s == '10' ? '발행' : s == '90' ? '실패' : '대기'; }
function collect(f) {
    callCmd('collectSave', { billId: f.billId.value, custId: f.custId.value, collectAmt: f.collectAmt.value, collectMethod: f.collectMethod.value }, function (r) {
        if (!r.ok) return alert(r.msg);
        callCmd('custCreditInfo', { custId: f.custId.value }, function (c) {
            alert('수금했습니다. 남은 금액 ' + fmt(r.remain) + ' · 여신상태 ' + c.creditStatusNm);
            location.reload();
        });
    });
}
</script>
<table class="grid"><tr><th>청구번호</th><th>거래처</th><th>청구일</th><th>합계</th><th>받은 금액</th><th>발행</th><th>수주 상태</th><th>수금</th></tr>
<%          for (Map<String, Object> r : rows) {
                long remain = toLong(r.get("TOTAL_AMT")) - toLong(r.get("PAID")); %>
<tr><td><%= r.get("BILL_ID") %></td><td><%= esc(r.get("CUST_NM")) %></td><td><%= r.get("BILL_DT") %></td><td class="num"><%= fmt(r.get("TOTAL_AMT")) %></td><td class="num"><%= fmt(r.get("PAID")) %></td>
    <td><script>document.write(issueText('<%= r.get("ISSUE_STATUS") %>'));</script> <%= esc(r.get("ETAX_NO")) %></td><td><%= codeNm(codes, "ORDER_STATUS", r.get("ORDER_STATUS")) %></td>
    <td><% if (remain > 0 && "10".equals(r.get("ISSUE_STATUS"))) { %><form onsubmit="collect(this); return false;">
        <input type="hidden" name="billId" value="<%= r.get("BILL_ID") %>"><input type="hidden" name="custId" value="<%= r.get("CUST_ID") %>">
        <input name="collectAmt" size="10" value="<%= remain %>"> <select name="collectMethod"><%= codeOpts(codes, "COLLECT_METHOD") %></select> <button>수금</button></form><% } %></td></tr>
<%          } %>
</table>
<%
        } else {
%>
<p>없는 화면입니다 : <%= esc(cmd) %></p>
<%
        }
    } catch (Exception e) {
%>
<p style="color:red">오류 : <%= esc(e.getMessage()) %></p>
<%
    } finally {
        closeAll(null, null, conn);
    }
%>
</div>
</body>
</html>
