function selectSmiley(str, name) {
  $.each($("#" + str + " .smi"), function(i, v) { $(v).removeClass('selected'); });
  $.each($("#" + str + " input[type=submit]"), function(i, v) { $(v).hide() });
  $("#" + str + " .s-" + name).addClass('selected');
  $("#" + str + " .b-" + name).show();
  $("#" + str + " input[name=smiley]").val(name);
}

function checkform(form_id) {
  if ($("#" + form_id + " textarea[name=message]").val().trim().length == 0) {
    alert("Can't post a blank message for you.. No, never!");
    return false;
  }
  return true;
}

function toggleEdit(id) {
  $("#edit_entry_message").val( $("#post-msg-" + id).text().trim() );
  $("#edit_entry input[name=id]").val( id );
  selectSmiley("edit_entry", $("#post-msg-" + id).attr("class"));
  $("#edit_entry").dialog({
    width: 595,
    closeOnEscape: true,
    modal: true,
    resizable: false
  });
}

valid_email_regx = /^([A-Za-z0-9_\-\.])+\@([A-Za-z0-9_\-\.])+\.([A-Za-z]{2,4})$/;

function validateInvite() {
   alert ("WOO")
   return valid_email_regx.test($("#submit_email"));
}

